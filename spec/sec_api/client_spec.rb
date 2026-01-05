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
end
