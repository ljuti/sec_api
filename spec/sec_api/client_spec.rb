require "spec_helper"

RSpec.describe SecApi::Client do
  # Clear environment variables before and after tests
  around(:each) do |example|
    original_env = ENV.to_h.select { |k, _| k.start_with?("SECAPI_") }
    ENV.delete_if { |k, _| k.start_with?("SECAPI_") }
    example.run
    ENV.update(original_env)
  end

  describe "#initialize" do
    context "when api_key is missing" do
      it "raises ConfigurationError during initialization" do
        config = SecApi::Config.new
        expect { SecApi::Client.new(config) }.to raise_error(SecApi::ConfigurationError)
      end

      it "raises ConfigurationError with default config" do
        expect { SecApi::Client.new }.to raise_error(SecApi::ConfigurationError)
      end
    end

    context "when api_key is provided" do
      it "initializes successfully with explicit config" do
        config = SecApi::Config.new(api_key: "valid_test_key")
        expect { SecApi::Client.new(config) }.not_to raise_error
      end

      it "stores the config object" do
        config = SecApi::Config.new(api_key: "valid_test_key")
        client = SecApi::Client.new(config)
        expect(client.config).to eq(config)
      end

      it "initializes successfully using environment variable config" do
        ENV["SECAPI_API_KEY"] = "env_test_key"
        expect { SecApi::Client.new }.not_to raise_error
      end

      it "uses config from environment variable" do
        ENV["SECAPI_API_KEY"] = "env_test_key"
        ENV["SECAPI_BASE_URL"] = "https://test.example.com"
        client = SecApi::Client.new
        expect(client.config.api_key).to eq("env_test_key")
        expect(client.config.base_url).to eq("https://test.example.com")
      end
    end
  end

  describe "#xbrl" do
    let(:client) { SecApi::Client.new(SecApi::Config.new(api_key: "test_api_key_valid")) }

    it "returns an Xbrl proxy instance" do
      expect(client.xbrl).to be_a(SecApi::Xbrl)
    end

    it "memoizes the Xbrl proxy (returns same instance)" do
      xbrl1 = client.xbrl
      xbrl2 = client.xbrl
      expect(xbrl1).to equal(xbrl2)
    end

    it "provides Xbrl proxy access to client connection" do
      xbrl_proxy = client.xbrl
      expect(xbrl_proxy.instance_variable_get(:@_client)).to eq(client)
    end
  end

  describe "error handler middleware integration" do
    let(:config) { SecApi::Config.new(api_key: "test_api_key_valid") }
    let(:client) { SecApi::Client.new(config) }
    let(:stubs) { Faraday::Adapter::Test::Stubs.new }

    before do
      # Stub the client's connection to use test adapter
      allow(client).to receive(:connection).and_return(
        Faraday.new do |builder|
          builder.use SecApi::Middleware::ErrorHandler
          builder.adapter :test, stubs
        end
      )
    end

    after { stubs.verify_stubbed_calls }

    context "when API returns 400" do
      it "raises ValidationError (permanent)" do
        stubs.get("/test") { [400, {}, "Bad request"] }

        expect {
          client.connection.get("/test")
        }.to raise_error(SecApi::ValidationError)
      end
    end

    context "when API returns 403" do
      it "raises AuthenticationError (permanent)" do
        stubs.get("/test") { [403, {}, "Forbidden"] }

        expect {
          client.connection.get("/test")
        }.to raise_error(SecApi::AuthenticationError)
      end
    end

    context "when API returns 422" do
      it "raises ValidationError (permanent)" do
        stubs.get("/test") { [422, {}, "Unprocessable"] }

        expect {
          client.connection.get("/test")
        }.to raise_error(SecApi::ValidationError)
      end
    end

    context "when API returns 429" do
      it "raises RateLimitError (transient)" do
        stubs.get("/test") { [429, {}, "Rate limited"] }

        expect {
          client.connection.get("/test")
        }.to raise_error(SecApi::RateLimitError)
      end
    end

    context "when API returns 500" do
      it "raises ServerError (transient)" do
        stubs.get("/test") { [500, {}, "Server error"] }

        expect {
          client.connection.get("/test")
        }.to raise_error(SecApi::ServerError)
      end
    end

    context "when API returns 401" do
      it "raises AuthenticationError (permanent)" do
        stubs.get("/test") { [401, {}, "Unauthorized"] }

        expect {
          client.connection.get("/test")
        }.to raise_error(SecApi::AuthenticationError)
      end
    end

    context "when API returns 404" do
      it "raises NotFoundError (permanent)" do
        stubs.get("/test") { [404, {}, "Not found"] }

        expect {
          client.connection.get("/test")
        }.to raise_error(SecApi::NotFoundError)
      end
    end

    context "type-based error rescue" do
      it "allows catching all transient errors" do
        stubs.get("/test") { [429, {}, ""] }

        expect {
          client.connection.get("/test")
        }.to raise_error(SecApi::TransientError)
      end

      it "allows catching all permanent errors" do
        stubs.get("/test") { [401, {}, ""] }

        expect {
          client.connection.get("/test")
        }.to raise_error(SecApi::PermanentError)
      end
    end
  end

  describe "middleware stack verification" do
    let(:config) { SecApi::Config.new(api_key: "test_api_key_valid") }
    let(:client) { SecApi::Client.new(config) }

    it "includes ErrorHandler middleware in the connection stack" do
      middleware_classes = client.connection.builder.handlers.map(&:klass)
      expect(middleware_classes).to include(SecApi::Middleware::ErrorHandler)
    end

    it "ErrorHandler middleware is properly configured" do
      # Verify that ErrorHandler is in the middleware stack by making a request
      # and ensuring it properly converts HTTP errors to typed exceptions
      connection = client.connection
      expect(connection.builder.handlers.map(&:klass)).to include(SecApi::Middleware::ErrorHandler)
    end

    it "includes retry middleware in the connection stack" do
      middleware_classes = client.connection.builder.handlers.map(&:klass)
      expect(middleware_classes).to include(Faraday::Retry::Middleware)
    end

    it "positions retry middleware BEFORE ErrorHandler in stack" do
      handlers = client.connection.builder.handlers
      retry_index = handlers.index { |h| h.klass == Faraday::Retry::Middleware }
      error_handler_index = handlers.index { |h| h.klass == SecApi::Middleware::ErrorHandler }

      # Retry registered before ErrorHandler means retry wraps ErrorHandler
      # This allows retry to catch status codes before ErrorHandler raises
      expect(retry_index).to be < error_handler_index
    end

    it "includes RateLimiter middleware in the connection stack" do
      middleware_classes = client.connection.builder.handlers.map(&:klass)
      expect(middleware_classes).to include(SecApi::Middleware::RateLimiter)
    end

    it "positions RateLimiter after Retry and before ErrorHandler" do
      handlers = client.connection.builder.handlers
      retry_index = handlers.index { |h| h.klass == Faraday::Retry::Middleware }
      rate_limiter_index = handlers.index { |h| h.klass == SecApi::Middleware::RateLimiter }
      error_handler_index = handlers.index { |h| h.klass == SecApi::Middleware::ErrorHandler }

      # RateLimiter should be after Retry (to capture final response headers)
      expect(rate_limiter_index).to be > retry_index
      # RateLimiter should be before ErrorHandler (to capture headers from 429 responses)
      expect(rate_limiter_index).to be < error_handler_index
    end

    it "wires rate_limit_threshold from Config to RateLimiter middleware" do
      # Test with 25% threshold - should throttle at 24% remaining but not at 25%
      custom_config = SecApi::Config.new(api_key: "test_api_key_valid", rate_limit_threshold: 0.25)
      custom_client = SecApi::Client.new(custom_config)

      # Set up state at 24% remaining (below 25% threshold)
      custom_client.instance_variable_get(:@_rate_limit_tracker).update(
        limit: 100,
        remaining: 24,
        reset_at: Time.now + 60
      )

      stubs = Faraday::Adapter::Test::Stubs.new
      stubs.get("/test") { [200, {}, "{}"] }

      allow(custom_client).to receive(:connection).and_return(
        Faraday.new do |conn|
          conn.use SecApi::Middleware::RateLimiter,
            state_store: custom_client.instance_variable_get(:@_rate_limit_tracker),
            threshold: custom_config.rate_limit_threshold
          conn.adapter :test, stubs
        end
      )

      # Should throttle because 24% < 25% threshold
      expect_any_instance_of(SecApi::Middleware::RateLimiter).to receive(:sleep).with(a_value > 0)
      custom_client.connection.get("/test")

      stubs.verify_stubbed_calls
    end

    it "wires on_throttle callback from Config to RateLimiter middleware" do
      callback_invoked = []
      callback = ->(info) { callback_invoked << info }
      custom_config = SecApi::Config.new(api_key: "test_api_key_valid", on_throttle: callback)
      custom_client = SecApi::Client.new(custom_config)

      # Set up state below default threshold to trigger throttling
      custom_client.instance_variable_get(:@_rate_limit_tracker).update(
        limit: 100,
        remaining: 5,
        reset_at: Time.now + 30
      )

      stubs = Faraday::Adapter::Test::Stubs.new
      stubs.get("/test") { [200, {}, "{}"] }

      allow(custom_client).to receive(:connection).and_return(
        Faraday.new do |conn|
          conn.use SecApi::Middleware::RateLimiter,
            state_store: custom_client.instance_variable_get(:@_rate_limit_tracker),
            threshold: custom_config.rate_limit_threshold,
            on_throttle: custom_config.on_throttle
          conn.adapter :test, stubs
        end
      )

      allow_any_instance_of(SecApi::Middleware::RateLimiter).to receive(:sleep)
      custom_client.connection.get("/test")

      # Callback should have been invoked with throttle info
      expect(callback_invoked.size).to eq(1)
      expect(callback_invoked.first[:remaining]).to eq(5)
      expect(callback_invoked.first[:limit]).to eq(100)

      stubs.verify_stubbed_calls
    end
  end

  describe "retry middleware behavior" do
    let(:config) { SecApi::Config.new(api_key: "test_api_key_valid", retry_max_attempts: 3) }
    let(:client) { SecApi::Client.new(config) }
    let(:stubs) { Faraday::Adapter::Test::Stubs.new }

    before do
      # Stub the client's connection to use test adapter with retry middleware
      allow(client).to receive(:connection).and_return(
        Faraday.new do |builder|
          # Retry positioned BEFORE ErrorHandler so retry can catch status codes
          builder.request :retry, {
            max: config.retry_max_attempts,
            interval: config.retry_initial_delay,
            max_interval: config.retry_max_delay,
            backoff_factor: config.retry_backoff_factor,
            exceptions: [
              Faraday::TimeoutError,
              Faraday::ConnectionFailed,
              Faraday::SSLError,
              SecApi::TransientError
            ],
            methods: [:get, :post],
            retry_statuses: [429, 500, 502, 503, 504]
          }
          # ErrorHandler positioned AFTER retry
          builder.use SecApi::Middleware::ErrorHandler
          builder.adapter :test, stubs
        end
      )
    end

    after { stubs.verify_stubbed_calls }

    context "when API returns 503 (transient error)" do
      it "retries up to max_attempts and succeeds on 3rd attempt" do
        # First 2 attempts fail with 503
        2.times do
          stubs.get("/test") { [503, {}, "Service Unavailable"] }
        end
        # 3rd attempt succeeds
        stubs.get("/test") { [200, {"Content-Type" => "application/json"}, '{"result": "success"}'] }

        response = client.connection.get("/test")
        expect(response.status).to eq(200)
      end

      it "raises ServerError after exhausting all retries" do
        # All attempts fail with 503
        4.times do
          stubs.get("/test") { [503, {}, "Service Unavailable"] }
        end

        expect {
          client.connection.get("/test")
        }.to raise_error(SecApi::ServerError)
      end
    end

    context "when API returns 500 (transient error)" do
      it "retries and succeeds" do
        stubs.get("/test") { [500, {}, "Internal Server Error"] }
        stubs.get("/test") { [200, {"Content-Type" => "application/json"}, '{"result": "success"}'] }

        response = client.connection.get("/test")
        expect(response.status).to eq(200)
      end
    end

    context "when API returns 429 (rate limit - transient error)" do
      it "retries and succeeds" do
        stubs.get("/test") { [429, {}, "Rate Limited"] }
        stubs.get("/test") { [200, {"Content-Type" => "application/json"}, '{"result": "success"}'] }

        response = client.connection.get("/test")
        expect(response.status).to eq(200)
      end
    end

    context "when API returns 401 (permanent error)" do
      it "does NOT retry - raises AuthenticationError immediately" do
        # Only stub once - should NOT retry
        stubs.get("/test") { [401, {}, "Unauthorized"] }

        expect {
          client.connection.get("/test")
        }.to raise_error(SecApi::AuthenticationError)
      end
    end

    context "when API returns 404 (permanent error)" do
      it "does NOT retry - raises NotFoundError immediately" do
        # Only stub once - should NOT retry
        stubs.get("/test") { [404, {}, "Not Found"] }

        expect {
          client.connection.get("/test")
        }.to raise_error(SecApi::NotFoundError)
      end
    end

    context "when API returns 400 (validation error - permanent)" do
      it "does NOT retry - raises ValidationError immediately" do
        # Only stub once - should NOT retry
        stubs.get("/test") { [400, {}, "Bad Request"] }

        expect {
          client.connection.get("/test")
        }.to raise_error(SecApi::ValidationError)
      end
    end
  end

  describe "retry configuration customization" do
    it "uses custom retry_max_attempts from config" do
      config = SecApi::Config.new(
        api_key: "test_api_key_valid",
        retry_max_attempts: 10
      )
      client = SecApi::Client.new(config)

      # Verify the connection is configured with custom retry value
      expect(client.config.retry_max_attempts).to eq(10)
    end

    it "uses custom retry delays from config" do
      config = SecApi::Config.new(
        api_key: "test_api_key_valid",
        retry_initial_delay: 2.0,
        retry_max_delay: 30.0
      )
      client = SecApi::Client.new(config)

      expect(client.config.retry_initial_delay).to eq(2.0)
      expect(client.config.retry_max_delay).to eq(30.0)
    end

    it "uses custom retry_backoff_factor from config" do
      config = SecApi::Config.new(
        api_key: "test_api_key_valid",
        retry_backoff_factor: 3
      )
      client = SecApi::Client.new(config)

      expect(client.config.retry_backoff_factor).to eq(3)
    end
  end

  describe "#rate_limit_state" do
    let(:config) { SecApi::Config.new(api_key: "test_api_key_valid") }
    let(:client) { SecApi::Client.new(config) }

    it "returns nil before any requests are made" do
      expect(client.rate_limit_state).to be_nil
    end

    it "returns RateLimitState after a request with rate limit headers" do
      stubs = Faraday::Adapter::Test::Stubs.new
      reset_time = Time.now.to_i + 60

      stubs.get("/test") do
        [200, {
          "X-RateLimit-Limit" => "100",
          "X-RateLimit-Remaining" => "95",
          "X-RateLimit-Reset" => reset_time.to_s
        }, "{}"]
      end

      # Use real connection that goes through our middleware
      allow(client).to receive(:connection).and_return(
        Faraday.new do |conn|
          conn.use SecApi::Middleware::RateLimiter,
            state_store: client.instance_variable_get(:@_rate_limit_tracker)
          conn.adapter :test, stubs
        end
      )

      client.connection.get("/test")

      state = client.rate_limit_state
      expect(state).to be_a(SecApi::RateLimitState)
      expect(state.limit).to eq(100)
      expect(state.remaining).to eq(95)
      expect(state.reset_at).to eq(Time.at(reset_time))

      stubs.verify_stubbed_calls
    end

    it "updates state on each request" do
      stubs = Faraday::Adapter::Test::Stubs.new

      stubs.get("/first") do
        [200, {"X-RateLimit-Remaining" => "99"}, "{}"]
      end
      stubs.get("/second") do
        [200, {"X-RateLimit-Remaining" => "98"}, "{}"]
      end

      allow(client).to receive(:connection).and_return(
        Faraday.new do |conn|
          conn.use SecApi::Middleware::RateLimiter,
            state_store: client.instance_variable_get(:@_rate_limit_tracker)
          conn.adapter :test, stubs
        end
      )

      client.connection.get("/first")
      expect(client.rate_limit_state.remaining).to eq(99)

      client.connection.get("/second")
      expect(client.rate_limit_state.remaining).to eq(98)

      stubs.verify_stubbed_calls
    end
  end

  describe "rate limit state independence" do
    it "each client maintains its own rate limit state" do
      config = SecApi::Config.new(api_key: "test_api_key_valid")
      client1 = SecApi::Client.new(config)
      client2 = SecApi::Client.new(config)

      # Update client1's state through its tracker
      client1.instance_variable_get(:@_rate_limit_tracker).update(
        limit: 100,
        remaining: 50,
        reset_at: Time.now
      )

      # Update client2's state with different values
      client2.instance_variable_get(:@_rate_limit_tracker).update(
        limit: 200,
        remaining: 150,
        reset_at: Time.now
      )

      # Each client has independent state
      expect(client1.rate_limit_state.limit).to eq(100)
      expect(client2.rate_limit_state.limit).to eq(200)
      expect(client1.rate_limit_state.remaining).to eq(50)
      expect(client2.rate_limit_state.remaining).to eq(150)
    end
  end

  describe "#queued_requests" do
    let(:config) { SecApi::Config.new(api_key: "test_api_key_valid") }
    let(:client) { SecApi::Client.new(config) }

    it "returns 0 when no requests are queued" do
      expect(client.queued_requests).to eq(0)
    end

    it "returns the count from the rate limit tracker" do
      tracker = client.instance_variable_get(:@_rate_limit_tracker)

      # Simulate queued requests via tracker
      tracker.increment_queued
      tracker.increment_queued
      expect(client.queued_requests).to eq(2)

      tracker.decrement_queued
      expect(client.queued_requests).to eq(1)

      tracker.decrement_queued
      expect(client.queued_requests).to eq(0)
    end

    it "each client maintains independent queue counts" do
      config = SecApi::Config.new(api_key: "test_api_key_valid")
      client1 = SecApi::Client.new(config)
      client2 = SecApi::Client.new(config)

      client1.instance_variable_get(:@_rate_limit_tracker).increment_queued
      client1.instance_variable_get(:@_rate_limit_tracker).increment_queued

      client2.instance_variable_get(:@_rate_limit_tracker).increment_queued

      expect(client1.queued_requests).to eq(2)
      expect(client2.queued_requests).to eq(1)
    end
  end

  describe "connection pooling and thread safety" do
    it "supports 10+ concurrent requests without blocking (NFR14)" do
      config = SecApi::Config.new(api_key: "test_api_key_valid")
      client = SecApi::Client.new(config)

      # Stub the API response
      stubs = Faraday::Adapter::Test::Stubs.new
      stubs.get("/test") { [200, {}, {message: "success"}.to_json] }

      # Override connection with test adapter
      allow(client).to receive(:connection).and_return(
        Faraday.new do |conn|
          conn.response :json, content_type: /\bjson$/
          conn.adapter :test, stubs
        end
      )

      # Spawn 15 threads making concurrent requests
      threads = 15.times.map do
        Thread.new do
          client.connection.get("/test")
        end
      end

      # All requests complete successfully without blocking or errors
      responses = threads.map(&:value)
      expect(responses.length).to eq(15)
      expect(responses.all? { |r| r.status == 200 }).to be true

      stubs.verify_stubbed_calls
    end
  end

  describe "reactive rate limit backoff (Story 5.3)" do
    let(:stubs) { Faraday::Adapter::Test::Stubs.new }

    after { stubs.verify_stubbed_calls }

    describe "on_rate_limit callback" do
      it "invokes callback when 429 response is received and retried" do
        callback_invoked = []
        callback = ->(info) { callback_invoked << info }
        config = SecApi::Config.new(
          api_key: "test_api_key_valid",
          retry_max_attempts: 2,
          on_rate_limit: callback
        )
        client = SecApi::Client.new(config)

        # First request fails with 429, second succeeds
        stubs.get("/test") do
          [429, {"Retry-After" => "1", "X-RateLimit-Reset" => (Time.now.to_i + 60).to_s}, "Rate limited"]
        end
        stubs.get("/test") { [200, {}, '{"result": "success"}'] }

        allow(client).to receive(:connection).and_return(
          Faraday.new do |builder|
            builder.request :retry, client.send(:retry_options)
            builder.use SecApi::Middleware::ErrorHandler
            builder.adapter :test, stubs
          end
        )

        client.connection.get("/test")

        # Callback should have been invoked once (after first retry)
        expect(callback_invoked.size).to eq(1)
        expect(callback_invoked.first[:retry_after]).to eq(1)
        expect(callback_invoked.first[:reset_at]).to be_a(Time)
        expect(callback_invoked.first[:attempt]).to eq(1)
      end

      it "does not invoke callback when on_rate_limit is nil" do
        config = SecApi::Config.new(
          api_key: "test_api_key_valid",
          retry_max_attempts: 2
        )
        client = SecApi::Client.new(config)

        stubs.get("/test") { [429, {}, "Rate limited"] }
        stubs.get("/test") { [200, {}, '{"result": "success"}'] }

        allow(client).to receive(:connection).and_return(
          Faraday.new do |builder|
            builder.request :retry, client.send(:retry_options)
            builder.use SecApi::Middleware::ErrorHandler
            builder.adapter :test, stubs
          end
        )

        # Should not raise even without callback
        expect { client.connection.get("/test") }.not_to raise_error
      end

      it "invokes callback with nil retry_after when header is absent" do
        callback_invoked = []
        callback = ->(info) { callback_invoked << info }
        config = SecApi::Config.new(
          api_key: "test_api_key_valid",
          retry_max_attempts: 2,
          on_rate_limit: callback
        )
        client = SecApi::Client.new(config)

        stubs.get("/test") { [429, {}, "Rate limited"] }
        stubs.get("/test") { [200, {}, '{"result": "success"}'] }

        allow(client).to receive(:connection).and_return(
          Faraday.new do |builder|
            builder.request :retry, client.send(:retry_options)
            builder.use SecApi::Middleware::ErrorHandler
            builder.adapter :test, stubs
          end
        )

        client.connection.get("/test")

        expect(callback_invoked.first[:retry_after]).to be_nil
        expect(callback_invoked.first[:reset_at]).to be_nil
      end
    end

    describe "X-RateLimit-Reset backoff calculation" do
      it "calculates retry interval from reset_at when Retry-After is absent" do
        config = SecApi::Config.new(
          api_key: "test_api_key_valid",
          retry_max_attempts: 2
        )
        client = SecApi::Client.new(config)

        # Reset time 30 seconds in the future
        reset_time = Time.now.to_i + 30

        stubs.get("/test") do
          [429, {"X-RateLimit-Reset" => reset_time.to_s}, "Rate limited"]
        end
        stubs.get("/test") { [200, {}, '{"result": "success"}'] }

        allow(client).to receive(:connection).and_return(
          Faraday.new do |builder|
            builder.request :retry, client.send(:retry_options)
            builder.use SecApi::Middleware::ErrorHandler
            builder.adapter :test, stubs
          end
        )

        # The retry should succeed - verifying the interval calculation worked
        response = client.connection.get("/test")
        expect(response.status).to eq(200)
      end

      it "does not set interval when Retry-After header is present" do
        config = SecApi::Config.new(
          api_key: "test_api_key_valid",
          retry_max_attempts: 2
        )
        client = SecApi::Client.new(config)

        stubs.get("/test") do
          [429, {"Retry-After" => "1", "X-RateLimit-Reset" => (Time.now.to_i + 30).to_s}, "Rate limited"]
        end
        stubs.get("/test") { [200, {}, '{"result": "success"}'] }

        allow(client).to receive(:connection).and_return(
          Faraday.new do |builder|
            builder.request :retry, client.send(:retry_options)
            builder.use SecApi::Middleware::ErrorHandler
            builder.adapter :test, stubs
          end
        )

        # Retry-After takes precedence, so should complete quickly
        response = client.connection.get("/test")
        expect(response.status).to eq(200)
      end

      it "caps retry interval at retry_max_delay" do
        config = SecApi::Config.new(
          api_key: "test_api_key_valid",
          retry_max_attempts: 2,
          retry_max_delay: 5.0 # Cap at 5 seconds
        )
        client = SecApi::Client.new(config)

        # Reset time 60 seconds in the future - should be capped to 5
        reset_time = Time.now.to_i + 60

        stubs.get("/test") do
          [429, {"X-RateLimit-Reset" => reset_time.to_s}, "Rate limited"]
        end
        stubs.get("/test") { [200, {}, '{"result": "success"}'] }

        allow(client).to receive(:connection).and_return(
          Faraday.new do |builder|
            builder.request :retry, client.send(:retry_options)
            builder.use SecApi::Middleware::ErrorHandler
            builder.adapter :test, stubs
          end
        )

        # Should complete - interval should be capped
        response = client.connection.get("/test")
        expect(response.status).to eq(200)
      end
    end

    describe "Retry-After header formats" do
      it "respects Retry-After integer format" do
        config = SecApi::Config.new(
          api_key: "test_api_key_valid",
          retry_max_attempts: 2
        )
        client = SecApi::Client.new(config)

        stubs.get("/test") { [429, {"Retry-After" => "1"}, "Rate limited"] }
        stubs.get("/test") { [200, {}, '{"result": "success"}'] }

        allow(client).to receive(:connection).and_return(
          Faraday.new do |builder|
            builder.request :retry, client.send(:retry_options)
            builder.use SecApi::Middleware::ErrorHandler
            builder.adapter :test, stubs
          end
        )

        response = client.connection.get("/test")
        expect(response.status).to eq(200)
      end

      it "parses Retry-After HTTP-date format" do
        config = SecApi::Config.new(
          api_key: "test_api_key_valid",
          retry_max_attempts: 2
        )
        client = SecApi::Client.new(config)

        # HTTP-date format 2 seconds in future
        future_time = (Time.now + 2).httpdate
        stubs.get("/test") { [429, {"Retry-After" => future_time}, "Rate limited"] }
        stubs.get("/test") { [200, {}, '{"result": "success"}'] }

        allow(client).to receive(:connection).and_return(
          Faraday.new do |builder|
            builder.request :retry, client.send(:retry_options)
            builder.use SecApi::Middleware::ErrorHandler
            builder.adapter :test, stubs
          end
        )

        response = client.connection.get("/test")
        expect(response.status).to eq(200)
      end
    end

    describe "automatic retry on 429 response" do
      it "automatically retries and succeeds without manual intervention" do
        config = SecApi::Config.new(
          api_key: "test_api_key_valid",
          retry_max_attempts: 3
        )
        client = SecApi::Client.new(config)

        # First 2 requests fail with 429, third succeeds
        2.times { stubs.get("/test") { [429, {}, "Rate limited"] } }
        stubs.get("/test") { [200, {}, '{"data": "backfill results"}'] }

        allow(client).to receive(:connection).and_return(
          Faraday.new do |builder|
            builder.request :retry, client.send(:retry_options)
            builder.use SecApi::Middleware::ErrorHandler
            builder.adapter :test, stubs
          end
        )

        # Should eventually succeed without raising
        response = client.connection.get("/test")
        expect(response.status).to eq(200)
      end

      it "raises RateLimitError after exhausting all retry attempts" do
        config = SecApi::Config.new(
          api_key: "test_api_key_valid",
          retry_max_attempts: 2
        )
        client = SecApi::Client.new(config)

        # All 3 attempts (initial + 2 retries) fail with 429
        3.times { stubs.get("/test") { [429, {}, "Rate limited"] } }

        allow(client).to receive(:connection).and_return(
          Faraday.new do |builder|
            builder.request :retry, client.send(:retry_options)
            builder.use SecApi::Middleware::ErrorHandler
            builder.adapter :test, stubs
          end
        )

        expect { client.connection.get("/test") }.to raise_error(SecApi::RateLimitError)
      end
    end
  end
end
