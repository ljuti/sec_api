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
end
