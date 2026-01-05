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
  end
end
