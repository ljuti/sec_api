require "anyway_config"

module SecApi
  # Configuration for the SecApi client.
  #
  # Supports configuration via:
  # - Constructor arguments
  # - YAML file (config/secapi.yml)
  # - Environment variables (SECAPI_API_KEY, SECAPI_BASE_URL, etc.)
  #
  # @example Basic configuration
  #   config = SecApi::Config.new(api_key: "your_api_key")
  #
  # @example With custom rate limit settings
  #   config = SecApi::Config.new(
  #     api_key: "your_api_key",
  #     rate_limit_threshold: 0.2,  # Throttle at 20% remaining
  #     on_throttle: ->(info) { Rails.logger.warn("Throttling: #{info}") }
  #   )
  #
  # @!attribute [rw] rate_limit_threshold
  #   @return [Float] Threshold for proactive throttling (0.0-1.0). When the
  #     percentage of remaining requests drops below this value, the middleware
  #     will sleep until the rate limit window resets. Default is 0.1 (10%).
  #     Set to 0.0 to disable proactive throttling, or 1.0 to always throttle.
  #
  # @!attribute [rw] on_throttle
  #   @return [Proc, nil] Optional callback invoked when proactive throttling occurs.
  #     Receives a hash with the following keys:
  #     - :remaining [Integer] - Requests remaining in current window
  #     - :limit [Integer] - Total requests allowed per window
  #     - :delay [Float] - Seconds the request will be delayed
  #     - :reset_at [Time] - When the rate limit window resets
  #
  # @!attribute [rw] on_rate_limit
  #   @return [Proc, nil] Optional callback invoked when a 429 rate limit response
  #     is received and will be retried. This is the reactive callback (after hitting
  #     the limit), distinct from on_throttle which is proactive (before hitting limit).
  #     Receives a hash with the following keys:
  #     - :retry_after [Integer, nil] - Seconds to wait (from Retry-After header)
  #     - :reset_at [Time, nil] - When the rate limit resets (from X-RateLimit-Reset)
  #     - :attempt [Integer] - Current retry attempt number
  #
  class Config < Anyway::Config
    config_name :secapi

    attr_config :api_key,
      :base_url,
      :retry_max_attempts,
      :retry_initial_delay,
      :retry_max_delay,
      :retry_backoff_factor,
      :request_timeout,
      :rate_limit_threshold,
      :on_retry,
      :on_throttle,
      :on_rate_limit

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
    #
    # @raise [ConfigurationError] if any configuration value is invalid
    # @return [void]
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

      if retry_backoff_factor < 2
        raise ConfigurationError, "retry_backoff_factor must be >= 2 for exponential backoff (use 2 for standard exponential: 1s, 2s, 4s, 8s...)"
      end

      # Rate limit threshold validation
      if rate_limit_threshold < 0 || rate_limit_threshold > 1
        raise ConfigurationError, "rate_limit_threshold must be between 0.0 and 1.0"
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
