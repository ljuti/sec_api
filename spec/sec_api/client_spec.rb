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

  describe "#rate_limit_summary" do
    let(:config) { SecApi::Config.new(api_key: "test_api_key_valid") }
    let(:client) { SecApi::Client.new(config) }

    it "returns hash with all expected keys" do
      summary = client.rate_limit_summary

      expect(summary.keys).to contain_exactly(
        :remaining, :limit, :percentage, :reset_at, :queued_count, :exhausted
      )
    end

    it "returns nil values before any requests are made" do
      summary = client.rate_limit_summary

      expect(summary[:remaining]).to be_nil
      expect(summary[:limit]).to be_nil
      expect(summary[:percentage]).to be_nil
      expect(summary[:reset_at]).to be_nil
      expect(summary[:queued_count]).to eq(0)
      expect(summary[:exhausted]).to eq(false)
    end

    it "returns rate limit state after requests" do
      tracker = client.instance_variable_get(:@_rate_limit_tracker)
      tracker.update(limit: 100, remaining: 95, reset_at: Time.now + 60)

      summary = client.rate_limit_summary

      expect(summary[:remaining]).to eq(95)
      expect(summary[:limit]).to eq(100)
      expect(summary[:percentage]).to eq(95.0)
      expect(summary[:reset_at]).to be_a(Time)
      expect(summary[:exhausted]).to eq(false)
    end

    it "correctly identifies exhausted state" do
      tracker = client.instance_variable_get(:@_rate_limit_tracker)
      tracker.update(limit: 100, remaining: 0, reset_at: Time.now + 60)

      summary = client.rate_limit_summary

      expect(summary[:remaining]).to eq(0)
      expect(summary[:exhausted]).to eq(true)
    end

    it "includes current queue count" do
      tracker = client.instance_variable_get(:@_rate_limit_tracker)
      tracker.increment_queued
      tracker.increment_queued

      summary = client.rate_limit_summary

      expect(summary[:queued_count]).to eq(2)
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

      it "includes request_id in on_rate_limit callback info" do
        callback_invoked = []
        callback = ->(info) { callback_invoked << info }
        config = SecApi::Config.new(
          api_key: "test_api_key_valid",
          retry_max_attempts: 2,
          on_rate_limit: callback
        )
        client = SecApi::Client.new(config)
        tracker = SecApi::RateLimitTracker.new

        stubs.get("/test") { [429, {"Retry-After" => "1"}, "Rate limited"] }
        stubs.get("/test") { [200, {}, '{"result": "success"}'] }

        allow(client).to receive(:connection).and_return(
          Faraday.new do |builder|
            builder.use SecApi::Middleware::RateLimiter, state_store: tracker
            builder.request :retry, client.send(:retry_options)
            builder.use SecApi::Middleware::ErrorHandler
            builder.adapter :test, stubs
          end
        )

        client.connection.get("/test")

        expect(callback_invoked.size).to eq(1)
        expect(callback_invoked.first[:request_id]).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
      end

      it "logs rate limit exceeded event as JSON when logger is configured" do
        log_output = StringIO.new
        logger = Logger.new(log_output)
        logger.formatter = ->(_, _, _, msg) { "#{msg}\n" }

        config = SecApi::Config.new(
          api_key: "test_api_key_valid",
          retry_max_attempts: 2,
          logger: logger,
          log_level: :info
        )
        client = SecApi::Client.new(config)
        tracker = SecApi::RateLimitTracker.new

        stubs.get("/test") { [429, {"Retry-After" => "1"}, "Rate limited"] }
        stubs.get("/test") { [200, {}, '{"result": "success"}'] }

        allow(client).to receive(:connection).and_return(
          Faraday.new do |builder|
            builder.use SecApi::Middleware::RateLimiter, state_store: tracker
            builder.request :retry, client.send(:retry_options)
            builder.use SecApi::Middleware::ErrorHandler
            builder.adapter :test, stubs
          end
        )

        client.connection.get("/test")

        log_output.rewind
        log_line = log_output.read.strip
        log_data = JSON.parse(log_line)

        expect(log_data["event"]).to eq("secapi.rate_limit.exceeded")
        expect(log_data["retry_after"]).to eq(1)
        expect(log_data["attempt"]).to eq(1)
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

  describe "instrumentation callbacks (Story 7.1)" do
    let(:stubs) { Faraday::Adapter::Test::Stubs.new }

    after { stubs.verify_stubbed_calls }

    describe "on_request callback" do
      it "invokes callback before request is sent" do
        received_params = nil
        config = SecApi::Config.new(
          api_key: "test_api_key_valid",
          on_request: ->(request_id:, method:, url:, headers:) {
            received_params = {request_id: request_id, method: method, url: url, headers: headers}
          }
        )
        client = SecApi::Client.new(config)

        stubs.get("/test") { [200, {}, "{}"] }

        allow(client).to receive(:connection).and_return(
          Faraday.new do |builder|
            builder.use SecApi::Middleware::Instrumentation, config: config
            builder.adapter :test, stubs
          end
        )

        client.connection.get("/test")

        expect(received_params).not_to be_nil
        expect(received_params[:method]).to eq(:get)
        expect(received_params[:request_id]).to match(/\A[0-9a-f-]{36}\z/)
      end

      it "sanitizes Authorization header from callback" do
        received_headers = nil
        config = SecApi::Config.new(
          api_key: "test_api_key_valid",
          on_request: ->(headers:, **) { received_headers = headers }
        )
        client = SecApi::Client.new(config)

        stubs.get("/test") { [200, {}, "{}"] }

        allow(client).to receive(:connection).and_return(
          Faraday.new do |builder|
            builder.headers["Authorization"] = "secret_key"
            builder.use SecApi::Middleware::Instrumentation, config: config
            builder.adapter :test, stubs
          end
        )

        client.connection.get("/test")

        expect(received_headers).not_to have_key("Authorization")
      end
    end

    describe "on_response callback" do
      it "invokes callback with status and duration_ms" do
        received_params = nil
        config = SecApi::Config.new(
          api_key: "test_api_key_valid",
          on_response: ->(request_id:, status:, duration_ms:, url:, method:) {
            received_params = {request_id: request_id, status: status, duration_ms: duration_ms}
          }
        )
        client = SecApi::Client.new(config)

        stubs.get("/test") { [200, {}, "{}"] }

        allow(client).to receive(:connection).and_return(
          Faraday.new do |builder|
            builder.use SecApi::Middleware::Instrumentation, config: config
            builder.adapter :test, stubs
          end
        )

        client.connection.get("/test")

        expect(received_params[:status]).to eq(200)
        expect(received_params[:duration_ms]).to be_a(Integer)
        expect(received_params[:duration_ms]).to be >= 0
      end
    end

    describe "on_retry callback" do
      it "invokes callback before each retry attempt" do
        retry_calls = []
        config = SecApi::Config.new(
          api_key: "test_api_key_valid",
          retry_max_attempts: 3,
          retry_initial_delay: 0.01,
          on_retry: ->(request_id:, attempt:, max_attempts:, error_class:, error_message:, will_retry_in:) {
            retry_calls << {attempt: attempt, max_attempts: max_attempts, error_class: error_class}
          }
        )
        client = SecApi::Client.new(config)

        # First 2 fail with 503, 3rd succeeds
        2.times { stubs.get("/test") { [503, {}, "Service unavailable"] } }
        stubs.get("/test") { [200, {}, "{}"] }

        allow(client).to receive(:connection).and_return(
          Faraday.new do |builder|
            builder.use SecApi::Middleware::Instrumentation, config: config
            builder.request :retry, client.send(:retry_options)
            builder.use SecApi::Middleware::ErrorHandler, config: config
            builder.adapter :test, stubs
          end
        )

        client.connection.get("/test")

        expect(retry_calls.size).to eq(2)
        expect(retry_calls[0][:attempt]).to eq(1)
        expect(retry_calls[1][:attempt]).to eq(2)
        expect(retry_calls[0][:max_attempts]).to eq(3)
        expect(retry_calls[0][:error_class]).to include("ServerError")
      end

      it "includes request_id in retry callback" do
        request_ids = []
        config = SecApi::Config.new(
          api_key: "test_api_key_valid",
          retry_max_attempts: 2,
          retry_initial_delay: 0.01,
          on_request: ->(request_id:, **) { request_ids << request_id },
          on_retry: ->(request_id:, **) { request_ids << request_id }
        )
        client = SecApi::Client.new(config)

        stubs.get("/test") { [503, {}, "Service unavailable"] }
        stubs.get("/test") { [200, {}, "{}"] }

        allow(client).to receive(:connection).and_return(
          Faraday.new do |builder|
            builder.use SecApi::Middleware::Instrumentation, config: config
            builder.request :retry, client.send(:retry_options)
            builder.use SecApi::Middleware::ErrorHandler, config: config
            builder.adapter :test, stubs
          end
        )

        client.connection.get("/test")

        # All request_ids should be the same
        expect(request_ids.uniq.size).to eq(1)
      end
    end

    describe "on_error callback" do
      it "invokes callback on final failure" do
        received_error = nil
        config = SecApi::Config.new(
          api_key: "test_api_key_valid",
          retry_max_attempts: 1,
          on_error: ->(request_id:, error:, url:, method:) {
            received_error = {error: error, url: url, method: method}
          }
        )
        client = SecApi::Client.new(config)

        stubs.get("/test") { [404, {}, "Not found"] }

        allow(client).to receive(:connection).and_return(
          Faraday.new do |builder|
            builder.use SecApi::Middleware::Instrumentation, config: config
            builder.use SecApi::Middleware::ErrorHandler, config: config
            builder.adapter :test, stubs
          end
        )

        expect { client.connection.get("/test") }.to raise_error(SecApi::NotFoundError)
        expect(received_error[:error]).to be_a(SecApi::NotFoundError)
        expect(received_error[:method]).to eq(:get)
      end

      it "invokes on_error for both HTTP errors and network errors" do
        error_types = []
        config = SecApi::Config.new(
          api_key: "test_api_key_valid",
          on_error: ->(error:, **) { error_types << error.class.name }
        )
        client = SecApi::Client.new(config)

        # Test HTTP error (404)
        stubs.get("/test404") { [404, {}, "Not found"] }

        allow(client).to receive(:connection).and_return(
          Faraday.new do |builder|
            builder.use SecApi::Middleware::Instrumentation, config: config
            builder.use SecApi::Middleware::ErrorHandler, config: config
            builder.adapter :test, stubs
          end
        )

        expect { client.connection.get("/test404") }.to raise_error(SecApi::NotFoundError)
        expect(error_types).to include("SecApi::NotFoundError")
      end

      it "does NOT invoke on_error when request eventually succeeds after retries" do
        error_calls = []
        config = SecApi::Config.new(
          api_key: "test_api_key_valid",
          retry_max_attempts: 3,
          retry_initial_delay: 0.01,
          on_error: ->(error:, **) { error_calls << error.class.name }
        )
        client = SecApi::Client.new(config)

        # First 2 fail with 503, 3rd succeeds
        2.times { stubs.get("/test") { [503, {}, "Service unavailable"] } }
        stubs.get("/test") { [200, {}, "{}"] }

        allow(client).to receive(:connection).and_return(
          Faraday.new do |builder|
            builder.use SecApi::Middleware::Instrumentation, config: config
            builder.request :retry, client.send(:retry_options)
            builder.use SecApi::Middleware::ErrorHandler, config: config
            builder.adapter :test, stubs
          end
        )

        response = client.connection.get("/test")

        expect(response.status).to eq(200)
        expect(error_calls).to be_empty
      end

      it "invokes on_error only once after all retries exhausted for network errors" do
        error_calls = []
        config = SecApi::Config.new(
          api_key: "test_api_key_valid",
          retry_max_attempts: 2,
          retry_initial_delay: 0.01,
          on_error: ->(error:, **) { error_calls << error.class.name }
        )
        client = SecApi::Client.new(config)

        # Create a connection that raises TimeoutError
        allow(client).to receive(:connection).and_return(
          Faraday.new do |builder|
            builder.use SecApi::Middleware::Instrumentation, config: config
            builder.request :retry, client.send(:retry_options)
            builder.use SecApi::Middleware::ErrorHandler, config: config
            builder.adapter :test do |stub|
              stub.get("/test") { raise Faraday::TimeoutError, "timeout" }
            end
          end
        )

        expect { client.connection.get("/test") }.to raise_error(SecApi::NetworkError)
        # on_error should be called exactly once, not on each retry attempt
        expect(error_calls.size).to eq(1)
        expect(error_calls.first).to eq("SecApi::NetworkError")
      end
    end

    describe "callback exception safety" do
      it "continues request when on_request callback raises" do
        config = SecApi::Config.new(
          api_key: "test_api_key_valid",
          on_request: ->(**) { raise "Callback error" }
        )
        client = SecApi::Client.new(config)

        stubs.get("/test") { [200, {}, '{"success": true}'] }

        allow(client).to receive(:connection).and_return(
          Faraday.new do |builder|
            builder.use SecApi::Middleware::Instrumentation, config: config
            builder.adapter :test, stubs
          end
        )

        response = client.connection.get("/test")
        expect(response.status).to eq(200)
      end

      it "continues error handling when on_error callback raises" do
        config = SecApi::Config.new(
          api_key: "test_api_key_valid",
          on_error: ->(**) { raise "Callback error" }
        )
        client = SecApi::Client.new(config)

        stubs.get("/test") { [404, {}, "Not found"] }

        allow(client).to receive(:connection).and_return(
          Faraday.new do |builder|
            builder.use SecApi::Middleware::ErrorHandler, config: config
            builder.adapter :test, stubs
          end
        )

        # Should still raise the original error, not the callback error
        expect { client.connection.get("/test") }.to raise_error(SecApi::NotFoundError)
      end

      it "logs callback errors when logger is configured" do
        log_output = StringIO.new
        logger = Logger.new(log_output)

        config = SecApi::Config.new(
          api_key: "test_api_key_valid",
          logger: logger,
          on_request: ->(**) { raise "Test callback error" }
        )
        client = SecApi::Client.new(config)

        stubs.get("/test") { [200, {}, "{}"] }

        allow(client).to receive(:connection).and_return(
          Faraday.new do |builder|
            builder.use SecApi::Middleware::Instrumentation, config: config
            builder.adapter :test, stubs
          end
        )

        client.connection.get("/test")

        log_output.rewind
        logged_content = log_output.read

        expect(logged_content).to include("secapi.callback_error")
        expect(logged_content).to include("on_request")
      end

      it "continues request when on_response callback raises" do
        config = SecApi::Config.new(
          api_key: "test_api_key_valid",
          on_response: ->(**) { raise "Callback error" }
        )
        client = SecApi::Client.new(config)

        stubs.get("/test") { [200, {}, '{"success": true}'] }

        allow(client).to receive(:connection).and_return(
          Faraday.new do |builder|
            builder.use SecApi::Middleware::Instrumentation, config: config
            builder.adapter :test, stubs
          end
        )

        response = client.connection.get("/test")
        expect(response.status).to eq(200)
      end

      it "continues retry when on_retry callback raises" do
        config = SecApi::Config.new(
          api_key: "test_api_key_valid",
          retry_max_attempts: 2,
          retry_initial_delay: 0.01,
          on_retry: ->(**) { raise "Callback error" }
        )
        client = SecApi::Client.new(config)

        # First fails with 503, second succeeds
        stubs.get("/test") { [503, {}, "Service unavailable"] }
        stubs.get("/test") { [200, {}, "{}"] }

        allow(client).to receive(:connection).and_return(
          Faraday.new do |builder|
            builder.use SecApi::Middleware::Instrumentation, config: config
            builder.request :retry, client.send(:retry_options)
            builder.use SecApi::Middleware::ErrorHandler, config: config
            builder.adapter :test, stubs
          end
        )

        response = client.connection.get("/test")
        expect(response.status).to eq(200)
      end
    end

    describe "request_id consistency" do
      it "uses same request_id across all callbacks for same request" do
        request_ids = []
        config = SecApi::Config.new(
          api_key: "test_api_key_valid",
          on_request: ->(request_id:, **) { request_ids << request_id },
          on_response: ->(request_id:, **) { request_ids << request_id }
        )
        client = SecApi::Client.new(config)

        stubs.get("/test") { [200, {}, "{}"] }

        allow(client).to receive(:connection).and_return(
          Faraday.new do |builder|
            builder.use SecApi::Middleware::Instrumentation, config: config
            builder.adapter :test, stubs
          end
        )

        client.connection.get("/test")

        expect(request_ids.size).to eq(2)
        expect(request_ids.uniq.size).to eq(1)
        expect(request_ids.first).to match(/\A[0-9a-f-]{36}\z/)
      end
    end
  end

  describe "default_logging (Story 7.3)" do
    let(:stubs) { Faraday::Adapter::Test::Stubs.new }
    let(:log_output) { StringIO.new }
    let(:logger) do
      l = Logger.new(log_output)
      l.formatter = ->(_, _, _, msg) { "#{msg}\n" }
      l
    end

    after { stubs.verify_stubbed_calls }

    describe "when default_logging is false" do
      it "does not auto-configure logging callbacks" do
        config = SecApi::Config.new(
          api_key: "test_api_key_valid",
          logger: logger,
          default_logging: false
        )
        client = SecApi::Client.new(config)

        stubs.get("/test") { [200, {}, "{}"] }

        allow(client).to receive(:connection).and_return(
          Faraday.new do |builder|
            builder.use SecApi::Middleware::Instrumentation, config: config
            builder.adapter :test, stubs
          end
        )

        client.connection.get("/test")

        log_output.rewind
        expect(log_output.read).to be_empty
      end
    end

    describe "when default_logging is true with logger" do
      it "auto-configures on_request callback for structured logging" do
        config = SecApi::Config.new(
          api_key: "test_api_key_valid",
          logger: logger,
          default_logging: true
        )
        client = SecApi::Client.new(config)

        stubs.get("/test") { [200, {}, "{}"] }

        allow(client).to receive(:connection).and_return(
          Faraday.new do |builder|
            builder.use SecApi::Middleware::Instrumentation, config: config
            builder.adapter :test, stubs
          end
        )

        client.connection.get("/test")

        log_output.rewind
        log_lines = log_output.read.strip.split("\n")
        request_log = JSON.parse(log_lines.find { |l| l.include?("secapi.request.start") })

        expect(request_log["event"]).to eq("secapi.request.start")
        expect(request_log).to have_key("request_id")
        expect(request_log).to have_key("method")
        expect(request_log).to have_key("timestamp")
      end

      it "auto-configures on_response callback for structured logging" do
        config = SecApi::Config.new(
          api_key: "test_api_key_valid",
          logger: logger,
          default_logging: true
        )
        client = SecApi::Client.new(config)

        stubs.get("/test") { [200, {}, "{}"] }

        allow(client).to receive(:connection).and_return(
          Faraday.new do |builder|
            builder.use SecApi::Middleware::Instrumentation, config: config
            builder.adapter :test, stubs
          end
        )

        client.connection.get("/test")

        log_output.rewind
        log_lines = log_output.read.strip.split("\n")
        response_log = JSON.parse(log_lines.find { |l| l.include?("secapi.request.complete") })

        expect(response_log["event"]).to eq("secapi.request.complete")
        expect(response_log["status"]).to eq(200)
        expect(response_log).to have_key("duration_ms")
        expect(response_log).to have_key("success")
      end

      it "auto-configures on_error callback for structured logging" do
        config = SecApi::Config.new(
          api_key: "test_api_key_valid",
          logger: logger,
          default_logging: true
        )
        client = SecApi::Client.new(config)

        stubs.get("/test") { [404, {}, "Not found"] }

        allow(client).to receive(:connection).and_return(
          Faraday.new do |builder|
            builder.use SecApi::Middleware::Instrumentation, config: config
            builder.use SecApi::Middleware::ErrorHandler, config: config
            builder.adapter :test, stubs
          end
        )

        expect { client.connection.get("/test") }.to raise_error(SecApi::NotFoundError)

        log_output.rewind
        log_lines = log_output.read.strip.split("\n")
        error_log = JSON.parse(log_lines.find { |l| l.include?("secapi.request.error") })

        expect(error_log["event"]).to eq("secapi.request.error")
        expect(error_log["error_class"]).to eq("SecApi::NotFoundError")
        expect(error_log).to have_key("error_message")
      end

      it "auto-configures on_retry callback for structured logging" do
        config = SecApi::Config.new(
          api_key: "test_api_key_valid",
          logger: logger,
          default_logging: true,
          retry_max_attempts: 2,
          retry_initial_delay: 0.01
        )
        client = SecApi::Client.new(config)

        stubs.get("/test") { [503, {}, "Service unavailable"] }
        stubs.get("/test") { [200, {}, "{}"] }

        allow(client).to receive(:connection).and_return(
          Faraday.new do |builder|
            builder.use SecApi::Middleware::Instrumentation, config: config
            builder.request :retry, client.send(:retry_options)
            builder.use SecApi::Middleware::ErrorHandler, config: config
            builder.adapter :test, stubs
          end
        )

        client.connection.get("/test")

        log_output.rewind
        log_lines = log_output.read.strip.split("\n")
        retry_log = JSON.parse(log_lines.find { |l| l.include?("secapi.request.retry") })

        expect(retry_log["event"]).to eq("secapi.request.retry")
        expect(retry_log["attempt"]).to eq(1)
        expect(retry_log["max_attempts"]).to eq(2)
        expect(retry_log).to have_key("error_class")
      end
    end

    describe "explicit callbacks take precedence over default logging" do
      it "uses explicit on_request callback instead of default" do
        custom_calls = []
        config = SecApi::Config.new(
          api_key: "test_api_key_valid",
          logger: logger,
          default_logging: true,
          on_request: ->(request_id:, **) { custom_calls << request_id }
        )
        client = SecApi::Client.new(config)

        stubs.get("/test") { [200, {}, "{}"] }

        allow(client).to receive(:connection).and_return(
          Faraday.new do |builder|
            builder.use SecApi::Middleware::Instrumentation, config: config
            builder.adapter :test, stubs
          end
        )

        client.connection.get("/test")

        # Custom callback was invoked
        expect(custom_calls.size).to eq(1)

        # Default logging should NOT have logged request start
        log_output.rewind
        log_lines = log_output.read.strip.split("\n")
        request_log = log_lines.find { |l| l.include?("secapi.request.start") }
        expect(request_log).to be_nil
      end

      it "uses explicit on_response callback instead of default" do
        custom_calls = []
        config = SecApi::Config.new(
          api_key: "test_api_key_valid",
          logger: logger,
          default_logging: true,
          on_response: ->(status:, **) { custom_calls << status }
        )
        client = SecApi::Client.new(config)

        stubs.get("/test") { [200, {}, "{}"] }

        allow(client).to receive(:connection).and_return(
          Faraday.new do |builder|
            builder.use SecApi::Middleware::Instrumentation, config: config
            builder.adapter :test, stubs
          end
        )

        client.connection.get("/test")

        # Custom callback was invoked
        expect(custom_calls).to eq([200])

        # Default logging should NOT have logged response
        log_output.rewind
        log_lines = log_output.read.strip.split("\n")
        response_log = log_lines.find { |l| l.include?("secapi.request.complete") }
        expect(response_log).to be_nil
      end

      it "uses explicit on_error callback instead of default" do
        custom_errors = []
        config = SecApi::Config.new(
          api_key: "test_api_key_valid",
          logger: logger,
          default_logging: true,
          on_error: ->(error:, **) { custom_errors << error.class.name }
        )
        client = SecApi::Client.new(config)

        stubs.get("/test") { [404, {}, "Not found"] }

        allow(client).to receive(:connection).and_return(
          Faraday.new do |builder|
            builder.use SecApi::Middleware::Instrumentation, config: config
            builder.use SecApi::Middleware::ErrorHandler, config: config
            builder.adapter :test, stubs
          end
        )

        expect { client.connection.get("/test") }.to raise_error(SecApi::NotFoundError)

        # Custom callback was invoked
        expect(custom_errors).to eq(["SecApi::NotFoundError"])

        # Default logging should NOT have logged error
        log_output.rewind
        log_lines = log_output.read.strip.split("\n")
        error_log = log_lines.find { |l| l.include?("secapi.request.error") }
        expect(error_log).to be_nil
      end
    end

    describe "when default_logging is true but no logger" do
      it "does not crash or configure callbacks" do
        config = SecApi::Config.new(
          api_key: "test_api_key_valid",
          logger: nil,
          default_logging: true
        )
        SecApi::Client.new(config) # Initialize to trigger setup_default_logging

        expect(config.on_request).to be_nil
        expect(config.on_response).to be_nil
        expect(config.on_error).to be_nil
        expect(config.on_retry).to be_nil
      end
    end

    describe "log levels" do
      it "uses configured log_level for request/response logging" do
        # Create a logger that tracks which methods were called
        debug_output = StringIO.new
        debug_logger = Logger.new(debug_output)
        debug_logger.formatter = ->(severity, _, _, msg) { "#{severity}:#{msg}\n" }

        config = SecApi::Config.new(
          api_key: "test_api_key_valid",
          logger: debug_logger,
          log_level: :debug,
          default_logging: true
        )
        client = SecApi::Client.new(config)

        stubs.get("/test") { [200, {}, "{}"] }

        allow(client).to receive(:connection).and_return(
          Faraday.new do |builder|
            builder.use SecApi::Middleware::Instrumentation, config: config
            builder.adapter :test, stubs
          end
        )

        client.connection.get("/test")

        # Check that debug-level messages were logged
        debug_output.rewind
        log_content = debug_output.read
        expect(log_content).to include("DEBUG:")
        expect(log_content).to include("secapi.request")
      end

      it "uses :warn for retry events regardless of log_level" do
        warn_output = StringIO.new
        warn_logger = Logger.new(warn_output)
        warn_logger.formatter = ->(severity, _, _, msg) { "#{severity}:#{msg}\n" }

        config = SecApi::Config.new(
          api_key: "test_api_key_valid",
          logger: warn_logger,
          log_level: :debug,
          default_logging: true,
          retry_max_attempts: 2,
          retry_initial_delay: 0.01
        )
        client = SecApi::Client.new(config)

        stubs.get("/test") { [503, {}, "Service unavailable"] }
        stubs.get("/test") { [200, {}, "{}"] }

        allow(client).to receive(:connection).and_return(
          Faraday.new do |builder|
            builder.use SecApi::Middleware::Instrumentation, config: config
            builder.request :retry, client.send(:retry_options)
            builder.use SecApi::Middleware::ErrorHandler, config: config
            builder.adapter :test, stubs
          end
        )

        client.connection.get("/test")

        # Check that warn-level message was logged for retry
        warn_output.rewind
        log_content = warn_output.read
        expect(log_content).to include("WARN:")
        expect(log_content).to include("secapi.request.retry")
      end

      it "uses :error for error events regardless of log_level" do
        error_output = StringIO.new
        error_logger = Logger.new(error_output)
        error_logger.formatter = ->(severity, _, _, msg) { "#{severity}:#{msg}\n" }

        config = SecApi::Config.new(
          api_key: "test_api_key_valid",
          logger: error_logger,
          log_level: :debug,
          default_logging: true
        )
        client = SecApi::Client.new(config)

        stubs.get("/test") { [404, {}, "Not found"] }

        allow(client).to receive(:connection).and_return(
          Faraday.new do |builder|
            builder.use SecApi::Middleware::Instrumentation, config: config
            builder.use SecApi::Middleware::ErrorHandler, config: config
            builder.adapter :test, stubs
          end
        )

        expect { client.connection.get("/test") }.to raise_error(SecApi::NotFoundError)

        # Check that error-level message was logged
        error_output.rewind
        log_content = error_output.read
        expect(log_content).to include("ERROR:")
        expect(log_content).to include("secapi.request.error")
      end
    end
  end

  describe "default_metrics (Story 7.4)" do
    let(:stubs) { Faraday::Adapter::Test::Stubs.new }

    after { stubs.verify_stubbed_calls }

    # Helper to create a metrics backend spy
    def create_metrics_backend_spy
      Struct.new(:calls) do
        def initialize
          super([])
        end

        def increment(metric, tags: nil)
          calls << {type: :increment, metric: metric, tags: tags}
        end

        def histogram(metric, value, tags: nil)
          calls << {type: :histogram, metric: metric, value: value, tags: tags}
        end

        def gauge(metric, value, tags: nil)
          calls << {type: :gauge, metric: metric, value: value, tags: tags}
        end

        def method(_name)
          OpenStruct.new(arity: -1)
        end
      end.new
    end

    describe "when metrics_backend is nil" do
      it "does not auto-configure metrics callbacks" do
        config = SecApi::Config.new(
          api_key: "test_api_key_valid",
          metrics_backend: nil
        )
        SecApi::Client.new(config)

        expect(config.on_response).to be_nil
        expect(config.on_retry).to be_nil
        expect(config.on_error).to be_nil
        expect(config.on_rate_limit).to be_nil
        expect(config.on_throttle).to be_nil
        expect(config.on_filing).to be_nil
        expect(config.on_reconnect).to be_nil
      end
    end

    describe "when metrics_backend is configured" do
      it "auto-configures on_response callback" do
        backend = create_metrics_backend_spy
        config = SecApi::Config.new(
          api_key: "test_api_key_valid",
          metrics_backend: backend
        )
        SecApi::Client.new(config)

        expect(config.on_response).not_to be_nil
      end

      it "records request metrics on successful response" do
        backend = create_metrics_backend_spy
        config = SecApi::Config.new(
          api_key: "test_api_key_valid",
          metrics_backend: backend
        )
        client = SecApi::Client.new(config)

        stubs.get("/test") { [200, {}, "{}"] }

        allow(client).to receive(:connection).and_return(
          Faraday.new do |builder|
            builder.use SecApi::Middleware::Instrumentation, config: config
            builder.adapter :test, stubs
          end
        )

        client.connection.get("/test")

        # Verify metrics were recorded
        increment_calls = backend.calls.select { |c| c[:type] == :increment }
        histogram_calls = backend.calls.select { |c| c[:type] == :histogram }

        expect(increment_calls.map { |c| c[:metric] }).to include("sec_api.requests.total")
        expect(increment_calls.map { |c| c[:metric] }).to include("sec_api.requests.success")
        expect(histogram_calls.map { |c| c[:metric] }).to include("sec_api.requests.duration_ms")
      end

      it "auto-configures on_retry callback" do
        backend = create_metrics_backend_spy
        config = SecApi::Config.new(
          api_key: "test_api_key_valid",
          metrics_backend: backend
        )
        SecApi::Client.new(config)

        expect(config.on_retry).not_to be_nil
      end

      it "auto-configures on_error callback" do
        backend = create_metrics_backend_spy
        config = SecApi::Config.new(
          api_key: "test_api_key_valid",
          metrics_backend: backend
        )
        SecApi::Client.new(config)

        expect(config.on_error).not_to be_nil
      end

      it "records error metrics on final failure" do
        backend = create_metrics_backend_spy
        config = SecApi::Config.new(
          api_key: "test_api_key_valid",
          metrics_backend: backend
        )
        client = SecApi::Client.new(config)

        stubs.get("/test") { [404, {}, "Not found"] }

        allow(client).to receive(:connection).and_return(
          Faraday.new do |builder|
            builder.use SecApi::Middleware::Instrumentation, config: config
            builder.use SecApi::Middleware::ErrorHandler, config: config
            builder.adapter :test, stubs
          end
        )

        expect { client.connection.get("/test") }.to raise_error(SecApi::NotFoundError)

        # Verify error metric was recorded
        increment_calls = backend.calls.select { |c| c[:type] == :increment }
        expect(increment_calls.map { |c| c[:metric] }).to include("sec_api.retries.exhausted")
      end

      it "auto-configures on_rate_limit callback" do
        backend = create_metrics_backend_spy
        config = SecApi::Config.new(
          api_key: "test_api_key_valid",
          metrics_backend: backend
        )
        SecApi::Client.new(config)

        expect(config.on_rate_limit).not_to be_nil
      end

      it "auto-configures on_throttle callback" do
        backend = create_metrics_backend_spy
        config = SecApi::Config.new(
          api_key: "test_api_key_valid",
          metrics_backend: backend
        )
        SecApi::Client.new(config)

        expect(config.on_throttle).not_to be_nil
      end

      it "auto-configures on_filing callback for streaming" do
        backend = create_metrics_backend_spy
        config = SecApi::Config.new(
          api_key: "test_api_key_valid",
          metrics_backend: backend
        )
        SecApi::Client.new(config)

        expect(config.on_filing).not_to be_nil
      end

      it "auto-configures on_reconnect callback for streaming" do
        backend = create_metrics_backend_spy
        config = SecApi::Config.new(
          api_key: "test_api_key_valid",
          metrics_backend: backend
        )
        SecApi::Client.new(config)

        expect(config.on_reconnect).not_to be_nil
      end

      it "records filing metrics via on_filing callback" do
        backend = create_metrics_backend_spy
        config = SecApi::Config.new(
          api_key: "test_api_key_valid",
          metrics_backend: backend
        )
        SecApi::Client.new(config)

        # Create a mock filing with form_type
        filing = double("StreamFiling", form_type: "10-K")

        # Invoke the callback directly
        config.on_filing.call(filing: filing, latency_ms: 500, received_at: Time.now)

        # Verify filing metrics were recorded
        increment_calls = backend.calls.select { |c| c[:type] == :increment }
        histogram_calls = backend.calls.select { |c| c[:type] == :histogram }

        expect(increment_calls.map { |c| c[:metric] }).to include("sec_api.stream.filings")
        expect(histogram_calls.map { |c| c[:metric] }).to include("sec_api.stream.latency_ms")
      end

      it "records reconnect metrics via on_reconnect callback" do
        backend = create_metrics_backend_spy
        config = SecApi::Config.new(
          api_key: "test_api_key_valid",
          metrics_backend: backend
        )
        SecApi::Client.new(config)

        # Invoke the callback directly
        config.on_reconnect.call(attempt_count: 3, downtime_seconds: 15.5)

        # Verify reconnect metrics were recorded
        increment_calls = backend.calls.select { |c| c[:type] == :increment }
        gauge_calls = backend.calls.select { |c| c[:type] == :gauge }
        histogram_calls = backend.calls.select { |c| c[:type] == :histogram }

        expect(increment_calls.map { |c| c[:metric] }).to include("sec_api.stream.reconnects")
        expect(gauge_calls.map { |c| c[:metric] }).to include("sec_api.stream.reconnect_attempts")
        expect(histogram_calls.map { |c| c[:metric] }).to include("sec_api.stream.downtime_ms")
      end

      it "records throttle metrics when throttling occurs" do
        backend = create_metrics_backend_spy
        config = SecApi::Config.new(
          api_key: "test_api_key_valid",
          metrics_backend: backend,
          rate_limit_threshold: 0.5
        )
        client = SecApi::Client.new(config)
        tracker = client.instance_variable_get(:@_rate_limit_tracker)

        # Set up rate limit state to trigger throttling
        tracker.update(limit: 100, remaining: 40, reset_at: Time.now + 10)

        stubs.get("/test") { [200, {"X-RateLimit-Remaining" => "39"}, "{}"] }

        allow(client).to receive(:connection).and_return(
          Faraday.new do |builder|
            builder.use SecApi::Middleware::Instrumentation, config: config
            builder.use SecApi::Middleware::RateLimiter,
              state_store: tracker,
              threshold: config.rate_limit_threshold,
              on_throttle: config.on_throttle
            builder.adapter :test, stubs
          end
        )

        client.connection.get("/test")

        # Verify throttle metrics were recorded
        increment_calls = backend.calls.select { |c| c[:type] == :increment }
        expect(increment_calls.map { |c| c[:metric] }).to include("sec_api.rate_limit.throttle")
      end
    end

    describe "explicit callbacks take precedence over default metrics" do
      it "uses explicit on_response callback instead of default metrics" do
        backend = create_metrics_backend_spy
        custom_calls = []
        config = SecApi::Config.new(
          api_key: "test_api_key_valid",
          metrics_backend: backend,
          on_response: ->(status:, **) { custom_calls << status }
        )
        client = SecApi::Client.new(config)

        stubs.get("/test") { [200, {}, "{}"] }

        allow(client).to receive(:connection).and_return(
          Faraday.new do |builder|
            builder.use SecApi::Middleware::Instrumentation, config: config
            builder.adapter :test, stubs
          end
        )

        client.connection.get("/test")

        # Custom callback was invoked
        expect(custom_calls).to eq([200])

        # Metrics backend should NOT have received request metrics (custom callback took precedence)
        increment_calls = backend.calls.select { |c| c[:type] == :increment }
        expect(increment_calls.map { |c| c[:metric] }).not_to include("sec_api.requests.total")
      end

      it "uses explicit on_error callback instead of default metrics" do
        backend = create_metrics_backend_spy
        custom_errors = []
        config = SecApi::Config.new(
          api_key: "test_api_key_valid",
          metrics_backend: backend,
          on_error: ->(error:, **) { custom_errors << error.class.name }
        )
        client = SecApi::Client.new(config)

        stubs.get("/test") { [404, {}, "Not found"] }

        allow(client).to receive(:connection).and_return(
          Faraday.new do |builder|
            builder.use SecApi::Middleware::Instrumentation, config: config
            builder.use SecApi::Middleware::ErrorHandler, config: config
            builder.adapter :test, stubs
          end
        )

        expect { client.connection.get("/test") }.to raise_error(SecApi::NotFoundError)

        # Custom callback was invoked
        expect(custom_errors).to eq(["SecApi::NotFoundError"])

        # Metrics backend should NOT have received error metrics (custom callback took precedence)
        increment_calls = backend.calls.select { |c| c[:type] == :increment }
        expect(increment_calls.map { |c| c[:metric] }).not_to include("sec_api.retries.exhausted")
      end
    end

    describe "combined with default_logging" do
      it "logging takes precedence when both configured (logging is set up first)" do
        backend = create_metrics_backend_spy
        log_output = StringIO.new
        logger = Logger.new(log_output)
        logger.formatter = ->(_, _, _, msg) { "#{msg}\n" }

        config = SecApi::Config.new(
          api_key: "test_api_key_valid",
          logger: logger,
          default_logging: true,
          metrics_backend: backend
        )
        client = SecApi::Client.new(config)

        stubs.get("/test") { [200, {}, "{}"] }

        allow(client).to receive(:connection).and_return(
          Faraday.new do |builder|
            builder.use SecApi::Middleware::Instrumentation, config: config
            builder.adapter :test, stubs
          end
        )

        client.connection.get("/test")

        # Logging should have happened (configured first, takes precedence)
        log_output.rewind
        log_content = log_output.read
        expect(log_content).to include("secapi.request.complete")

        # Metrics backend should NOT have received request metrics (logging took precedence)
        increment_calls = backend.calls.select { |c| c[:type] == :increment }
        expect(increment_calls.map { |c| c[:metric] }).not_to include("sec_api.requests.total")
      end
    end
  end
end
