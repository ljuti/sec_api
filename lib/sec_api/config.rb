require "anyway_config"

module SecApi
  class Config < Anyway::Config
    config_name :secapi

    attr_config :api_key,
                :base_url,
                :retry_max_attempts,
                :retry_initial_delay,
                :retry_max_delay,
                :request_timeout,
                :rate_limit_threshold

    # Sensible defaults
    def initialize(*)
      super
      self.base_url ||= "https://api.sec-api.io"
      self.retry_max_attempts ||= 5
      self.retry_initial_delay ||= 1.0
      self.retry_max_delay ||= 60.0
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