require "anyway_config"

module SecApi
  class Config < Anyway::Config
    config_name :secapi

    attr_config :api_key,
      :base_url,
      :retry_max_attempts,
      :retry_initial_delay,
      :retry_max_delay,
      :retry_backoff_factor,
      :request_timeout,
      :rate_limit_threshold

    # Sensible defaults
    def initialize(*)
      super
      self.base_url ||= "https://api.sec-api.io"
      self.retry_max_attempts ||= 5
      self.retry_initial_delay ||= 1.0
      self.retry_max_delay ||= 60.0
      self.retry_backoff_factor ||= 2
      self.request_timeout ||= 30
      self.rate_limit_threshold ||= 0.1
    end

    # Validation called by Client
    def validate!
      if api_key.nil? || api_key.empty?
        raise ConfigurationError, missing_api_key_message
      end

      if api_key.include?("your_api_key_here") || api_key.length < 10
        raise ConfigurationError, invalid_api_key_message
      end

      # Retry configuration validation
      if retry_max_attempts <= 0
        raise ConfigurationError, "retry_max_attempts must be positive"
      end

      if retry_initial_delay <= 0
        raise ConfigurationError, "retry_initial_delay must be positive"
      end

      if retry_max_delay <= 0
        raise ConfigurationError, "retry_max_delay must be positive"
      end

      if retry_max_delay < retry_initial_delay
        raise ConfigurationError, "retry_max_delay must be >= retry_initial_delay"
      end

      if retry_backoff_factor < 1
        raise ConfigurationError, "retry_backoff_factor must be >= 1"
      end
    end

    private

    def missing_api_key_message
      "api_key is required. " \
      "Configure in config/secapi.yml or set SECAPI_API_KEY environment variable. " \
      "Get your API key from https://sec-api.io"
    end

    def invalid_api_key_message
      "api_key appears to be invalid (placeholder or too short). " \
      "Expected a valid API key from https://sec-api.io. " \
      "Check your configuration in config/secapi.yml or SECAPI_API_KEY environment variable."
    end
  end
end
