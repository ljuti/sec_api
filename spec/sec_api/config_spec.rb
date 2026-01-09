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
        retry_backoff_factor: 3,
        request_timeout: 60,
        rate_limit_threshold: 0.2
      )

      expect(config.api_key).to eq("test_key_valid")
      expect(config.base_url).to eq("https://custom.com")
      expect(config.retry_max_attempts).to eq(10)
      expect(config.retry_initial_delay).to eq(2.0)
      expect(config.retry_max_delay).to eq(120.0)
      expect(config.retry_backoff_factor).to eq(3)
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

    it "sets retry_backoff_factor to 2 (exponential)" do
      expect(config.retry_backoff_factor).to eq(2)
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

    context "when retry configuration is invalid" do
      it "raises ConfigurationError when retry_max_attempts is zero" do
        config = SecApi::Config.new(api_key: "valid_test_key_123", retry_max_attempts: 0)
        expect { config.validate! }.to raise_error(
          SecApi::ConfigurationError,
          /retry_max_attempts must be positive/
        )
      end

      it "raises ConfigurationError when retry_max_attempts is negative" do
        config = SecApi::Config.new(api_key: "valid_test_key_123", retry_max_attempts: -1)
        expect { config.validate! }.to raise_error(
          SecApi::ConfigurationError,
          /retry_max_attempts must be positive/
        )
      end

      it "raises ConfigurationError when retry_initial_delay is zero" do
        config = SecApi::Config.new(api_key: "valid_test_key_123", retry_initial_delay: 0)
        expect { config.validate! }.to raise_error(
          SecApi::ConfigurationError,
          /retry_initial_delay must be positive/
        )
      end

      it "raises ConfigurationError when retry_initial_delay is negative" do
        config = SecApi::Config.new(api_key: "valid_test_key_123", retry_initial_delay: -1.0)
        expect { config.validate! }.to raise_error(
          SecApi::ConfigurationError,
          /retry_initial_delay must be positive/
        )
      end

      it "raises ConfigurationError when retry_max_delay is zero" do
        config = SecApi::Config.new(api_key: "valid_test_key_123", retry_max_delay: 0)
        expect { config.validate! }.to raise_error(
          SecApi::ConfigurationError,
          /retry_max_delay must be positive/
        )
      end

      it "raises ConfigurationError when retry_max_delay is negative" do
        config = SecApi::Config.new(api_key: "valid_test_key_123", retry_max_delay: -60.0)
        expect { config.validate! }.to raise_error(
          SecApi::ConfigurationError,
          /retry_max_delay must be positive/
        )
      end

      it "raises ConfigurationError when retry_max_delay < retry_initial_delay" do
        config = SecApi::Config.new(
          api_key: "valid_test_key_123",
          retry_initial_delay: 10.0,
          retry_max_delay: 5.0
        )
        expect { config.validate! }.to raise_error(
          SecApi::ConfigurationError,
          /retry_max_delay must be >= retry_initial_delay/
        )
      end

      it "raises ConfigurationError when retry_backoff_factor is less than 2" do
        config = SecApi::Config.new(api_key: "valid_test_key_123", retry_backoff_factor: 1)
        expect { config.validate! }.to raise_error(
          SecApi::ConfigurationError,
          /retry_backoff_factor must be >= 2/
        )
      end
    end

    context "when retry configuration is valid" do
      it "does not raise error with custom retry values" do
        config = SecApi::Config.new(
          api_key: "valid_test_key_123",
          retry_max_attempts: 3,
          retry_initial_delay: 2.0,
          retry_max_delay: 30.0,
          retry_backoff_factor: 2
        )
        expect { config.validate! }.not_to raise_error
      end
    end

    context "when rate_limit_threshold is invalid" do
      it "raises ConfigurationError when threshold is negative" do
        config = SecApi::Config.new(api_key: "valid_test_key_123", rate_limit_threshold: -0.1)
        expect { config.validate! }.to raise_error(
          SecApi::ConfigurationError,
          /rate_limit_threshold must be between 0\.0 and 1\.0/
        )
      end

      it "raises ConfigurationError when threshold is greater than 1.0" do
        config = SecApi::Config.new(api_key: "valid_test_key_123", rate_limit_threshold: 1.5)
        expect { config.validate! }.to raise_error(
          SecApi::ConfigurationError,
          /rate_limit_threshold must be between 0\.0 and 1\.0/
        )
      end
    end

    context "when rate_limit_threshold is valid" do
      it "accepts 0.0 (never throttle)" do
        config = SecApi::Config.new(api_key: "valid_test_key_123", rate_limit_threshold: 0.0)
        expect { config.validate! }.not_to raise_error
      end

      it "accepts 1.0 (always throttle)" do
        config = SecApi::Config.new(api_key: "valid_test_key_123", rate_limit_threshold: 1.0)
        expect { config.validate! }.not_to raise_error
      end

      it "accepts 0.2 (20% threshold)" do
        config = SecApi::Config.new(api_key: "valid_test_key_123", rate_limit_threshold: 0.2)
        expect { config.validate! }.not_to raise_error
      end
    end
  end

  describe "on_throttle callback" do
    it "accepts a callback proc" do
      callback = ->(info) { puts info }
      config = SecApi::Config.new(api_key: "valid_test_key_123", on_throttle: callback)
      expect(config.on_throttle).to eq(callback)
    end

    it "defaults to nil when not provided" do
      config = SecApi::Config.new(api_key: "valid_test_key_123")
      expect(config.on_throttle).to be_nil
    end
  end

  describe "on_callback_error callback (Story 6.3)" do
    it "accepts a callback proc" do
      callback = ->(info) { puts info[:error].message }
      config = SecApi::Config.new(api_key: "valid_test_key_123", on_callback_error: callback)
      expect(config.on_callback_error).to eq(callback)
    end

    it "defaults to nil when not provided" do
      config = SecApi::Config.new(api_key: "valid_test_key_123")
      expect(config.on_callback_error).to be_nil
    end

    it "can be invoked with error context hash" do
      received_info = nil
      callback = ->(info) { received_info = info }
      config = SecApi::Config.new(api_key: "valid_test_key_123", on_callback_error: callback)

      # Simulate callback invocation
      test_error = RuntimeError.new("Test error")
      config.on_callback_error.call(
        error: test_error,
        filing: nil,
        accession_no: "0001-24-001",
        ticker: "AAPL"
      )

      expect(received_info[:error]).to eq(test_error)
      expect(received_info[:accession_no]).to eq("0001-24-001")
      expect(received_info[:ticker]).to eq("AAPL")
    end
  end

  describe "logger configuration" do
    it "accepts a Logger instance" do
      logger = Logger.new($stdout)
      config = SecApi::Config.new(api_key: "valid_test_key_123", logger: logger)
      expect(config.logger).to be_a(Logger)
    end

    it "defaults to nil when not provided" do
      config = SecApi::Config.new(api_key: "valid_test_key_123")
      expect(config.logger).to be_nil
    end

    it "accepts log_level as a symbol" do
      config = SecApi::Config.new(api_key: "valid_test_key_123", log_level: :debug)
      expect(config.log_level).to eq(:debug)
    end

    it "defaults log_level to :info when not provided" do
      config = SecApi::Config.new(api_key: "valid_test_key_123")
      expect(config.log_level).to eq(:info)
    end
  end
end
