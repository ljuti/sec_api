require "spec_helper"
require "fileutils"

RSpec.describe SecApi::Config do
  # Clear environment variables before and after tests
  around(:each) do |example|
    original_env = ENV.to_h.select { |k, _| k.start_with?("SECAPI_") }
    ENV.delete_if { |k, _| k.start_with?("SECAPI_") }
    example.run
    ENV.update(original_env)
  end

  describe "loading from environment variables" do
    it "loads api_key from SECAPI_API_KEY" do
      ENV["SECAPI_API_KEY"] = "env_test_key"
      config = SecApi::Config.new
      expect(config.api_key).to eq("env_test_key")
    end

    it "loads base_url from SECAPI_BASE_URL" do
      ENV["SECAPI_BASE_URL"] = "https://test.example.com"
      config = SecApi::Config.new(api_key: "test_key_valid")
      expect(config.base_url).to eq("https://test.example.com")
    end

    it "environment variable overrides defaults" do
      # Env var overrides default value
      ENV["SECAPI_BASE_URL"] = "https://env.example.com"
      config = SecApi::Config.new(api_key: "test_key_valid")
      # Environment variable overrides the default base_url
      expect(config.base_url).to eq("https://env.example.com")
    end

    it "uses default when env var not set" do
      config = SecApi::Config.new(api_key: "test_key_valid")
      expect(config.base_url).to eq("https://api.sec-api.io")
    end
  end

  describe "loading from YAML file" do
    it "loads configuration from actual YAML file when config/secapi.yml exists" do
      # Create temporary config file
      FileUtils.mkdir_p("config")
      File.write("config/secapi.yml", <<~YAML)
        api_key: yaml_file_test_key
        base_url: https://yaml.test.example.com
        retry_max_attempts: 3
      YAML

      begin
        # anyway_config automatically loads from config/secapi.yml
        config = SecApi::Config.new

        # Verify it loaded from YAML file
        expect(config.api_key).to eq("yaml_file_test_key")
        expect(config.base_url).to eq("https://yaml.test.example.com")
        expect(config.retry_max_attempts).to eq(3)
      ensure
        # Clean up
        File.delete("config/secapi.yml") if File.exist?("config/secapi.yml")
      end
    end
  end

  describe "loading from initialization (YAML simulation)" do
    it "loads api_key from initialization params" do
      config = SecApi::Config.new(api_key: "yaml_test_key")
      expect(config.api_key).to eq("yaml_test_key")
    end

    it "loads base_url from initialization params" do
      config = SecApi::Config.new(api_key: "test_key_valid", base_url: "https://custom.example.com")
      expect(config.base_url).to eq("https://custom.example.com")
    end

    it "loads all configuration values from initialization" do
      config = SecApi::Config.new(
        api_key: "test_key_valid",
        base_url: "https://custom.com",
        retry_max_attempts: 10,
        retry_initial_delay: 2.0,
        retry_max_delay: 120.0,
        request_timeout: 60,
        rate_limit_threshold: 0.2
      )

      expect(config.api_key).to eq("test_key_valid")
      expect(config.base_url).to eq("https://custom.com")
      expect(config.retry_max_attempts).to eq(10)
      expect(config.retry_initial_delay).to eq(2.0)
      expect(config.retry_max_delay).to eq(120.0)
      expect(config.request_timeout).to eq(60)
      expect(config.rate_limit_threshold).to eq(0.2)
    end
  end

  describe "default configuration values" do
    let(:config) { SecApi::Config.new(api_key: "test_key_valid") }

    it "sets base_url to production API endpoint" do
      expect(config.base_url).to eq("https://api.sec-api.io")
    end

    it "sets retry_max_attempts to 5" do
      expect(config.retry_max_attempts).to eq(5)
    end

    it "sets retry_initial_delay to 1.0 seconds" do
      expect(config.retry_initial_delay).to eq(1.0)
    end

    it "sets retry_max_delay to 60.0 seconds" do
      expect(config.retry_max_delay).to eq(60.0)
    end

    it "sets request_timeout to 30 seconds" do
      expect(config.request_timeout).to eq(30)
    end

    it "sets rate_limit_threshold to 0.1 (10%)" do
      expect(config.rate_limit_threshold).to eq(0.1)
    end

    it "does not set default for api_key (required configuration)" do
      config = SecApi::Config.new
      expect(config.api_key).to be_nil
    end
  end

  describe "#validate!" do
    context "when api_key is missing" do
      it "raises ConfigurationError" do
        config = SecApi::Config.new
        expect { config.validate! }.to raise_error(SecApi::ConfigurationError)
      end

      it "provides actionable error message with instructions" do
        config = SecApi::Config.new
        expect { config.validate! }.to raise_error(
          SecApi::ConfigurationError,
          /api_key is required/
        )
      end

      it "includes configuration instructions in error message" do
        config = SecApi::Config.new
        expect { config.validate! }.to raise_error(
          SecApi::ConfigurationError,
          /config\/secapi\.yml/
        )
      end

      it "includes environment variable instructions in error message" do
        config = SecApi::Config.new
        expect { config.validate! }.to raise_error(
          SecApi::ConfigurationError,
          /SECAPI_API_KEY/
        )
      end
    end

    context "when api_key is empty string" do
      it "raises ConfigurationError" do
        config = SecApi::Config.new(api_key: "")
        expect { config.validate! }.to raise_error(SecApi::ConfigurationError)
      end
    end

    context "when api_key is placeholder value" do
      it "raises ConfigurationError for 'your_api_key_here'" do
        config = SecApi::Config.new(api_key: "your_api_key_here")
        expect { config.validate! }.to raise_error(
          SecApi::ConfigurationError,
          /appears to be invalid/
        )
      end
    end

    context "when api_key is too short" do
      it "raises ConfigurationError for keys shorter than 10 characters" do
        config = SecApi::Config.new(api_key: "short")
        expect { config.validate! }.to raise_error(
          SecApi::ConfigurationError,
          /appears to be invalid/
        )
      end
    end

    context "when api_key is present and valid" do
      it "does not raise error" do
        config = SecApi::Config.new(api_key: "valid_test_key_123")
        expect { config.validate! }.not_to raise_error
      end
    end
  end
end
