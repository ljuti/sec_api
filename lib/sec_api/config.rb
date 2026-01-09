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
  #     - :request_id [String] - UUID for tracing this request across callbacks
  #
  #   @example New Relic integration
  #     config = SecApi::Config.new(
  #       api_key: "...",
  #       on_throttle: ->(info) {
  #         NewRelic::Agent.record_custom_event(
  #           "SecApiRateLimitThrottle",
  #           remaining: info[:remaining],
  #           delay: info[:delay],
  #           request_id: info[:request_id]
  #         )
  #       }
  #     )
  #
  #   @example Datadog StatsD integration
  #     require 'datadog/statsd'
  #     statsd = Datadog::Statsd.new('localhost', 8125)
  #
  #     config = SecApi::Config.new(
  #       api_key: "...",
  #       on_throttle: ->(info) {
  #         statsd.increment('sec_api.rate_limit.throttle')
  #         statsd.gauge('sec_api.rate_limit.remaining', info[:remaining])
  #         statsd.histogram('sec_api.rate_limit.delay', info[:delay])
  #       }
  #     )
  #
  #   @example StatsD integration
  #     config = SecApi::Config.new(
  #       api_key: "...",
  #       on_throttle: ->(info) {
  #         StatsD.increment("sec_api.throttle")
  #         StatsD.gauge("sec_api.remaining", info[:remaining])
  #       }
  #     )
  #
  # @!attribute [rw] on_rate_limit
  #   @return [Proc, nil] Optional callback invoked when a 429 rate limit response
  #     is received and will be retried. This is the reactive callback (after hitting
  #     the limit), distinct from on_throttle which is proactive (before hitting limit).
  #     Receives a hash with the following keys:
  #     - :retry_after [Integer, nil] - Seconds to wait (from Retry-After header)
  #     - :reset_at [Time, nil] - When the rate limit resets (from X-RateLimit-Reset)
  #     - :attempt [Integer] - Current retry attempt number
  #     - :request_id [String, nil] - UUID for tracing this request across callbacks
  #
  #   @example New Relic integration for 429 responses
  #     config = SecApi::Config.new(
  #       api_key: "...",
  #       on_rate_limit: ->(info) {
  #         NewRelic::Agent.record_custom_event(
  #           "SecApiRateLimit429",
  #           retry_after: info[:retry_after],
  #           attempt: info[:attempt],
  #           request_id: info[:request_id]
  #         )
  #       }
  #     )
  #
  #   @example Alert threshold recommendation
  #     # Consider alerting when on_rate_limit is invoked frequently:
  #     # - Warning: >5 rate limit hits per minute
  #     # - Critical: >20 rate limit hits per minute
  #
  # @!attribute [rw] queue_wait_warning_threshold
  #   @return [Integer] Threshold in seconds for excessive wait warnings.
  #     When a request is queued and the wait time exceeds this threshold,
  #     the on_excessive_wait callback is invoked. Default is 300 (5 minutes).
  #
  # @!attribute [rw] on_queue
  #   @return [Proc, nil] Optional callback invoked when a request is queued
  #     due to exhausted rate limit (remaining = 0). Receives a hash with:
  #     - :queue_size [Integer] - Number of requests currently queued
  #     - :wait_time [Float] - Estimated seconds until rate limit resets
  #     - :reset_at [Time] - When the rate limit window resets
  #     - :request_id [String] - UUID for tracing this request across callbacks
  #
  #   @example Datadog queue depth monitoring
  #     statsd = Datadog::Statsd.new('localhost', 8125)
  #
  #     config = SecApi::Config.new(
  #       api_key: "...",
  #       on_queue: ->(info) {
  #         statsd.gauge('sec_api.rate_limit.queue_size', info[:queue_size])
  #         statsd.histogram('sec_api.rate_limit.wait_time', info[:wait_time])
  #       }
  #     )
  #
  # @!attribute [rw] on_excessive_wait
  #   @return [Proc, nil] Optional callback invoked when queue wait time exceeds
  #     queue_wait_warning_threshold. The request continues waiting after callback.
  #     Receives a hash with:
  #     - :wait_time [Float] - Seconds the request will wait
  #     - :threshold [Integer] - The configured warning threshold
  #     - :reset_at [Time] - When the rate limit resets
  #     - :request_id [String] - UUID for tracing this request across callbacks
  #
  # @!attribute [rw] on_dequeue
  #   @return [Proc, nil] Optional callback invoked when a request exits the queue
  #     after waiting for rate limit reset. Receives a hash with:
  #     - :queue_size [Integer] - Number of requests remaining in queue
  #     - :waited [Float] - Actual seconds the request waited
  #     - :request_id [String] - UUID for tracing this request across callbacks
  #
  # @!attribute [rw] logger
  #   @return [Logger, nil] Optional logger instance for structured rate limit logging.
  #     When configured, the middleware will log rate limit events (throttle, queue, 429)
  #     as JSON for compatibility with monitoring tools like ELK, Splunk, and Datadog.
  #     Compatible with Ruby Logger and ActiveSupport::Logger interfaces.
  #     Set to nil (default) to disable logging.
  #
  #   @example Using Rails logger
  #     config = SecApi::Config.new(
  #       api_key: "...",
  #       logger: Rails.logger,
  #       log_level: :info
  #     )
  #
  #   @example Log output format (JSON)
  #     # {"event":"secapi.rate_limit.throttle","request_id":"abc-123","remaining":5,"delay":30.2}
  #     # {"event":"secapi.rate_limit.queue","request_id":"abc-123","queue_size":3,"wait_time":60}
  #     # {"event":"secapi.rate_limit.exceeded","request_id":"abc-123","retry_after":30,"attempt":1}
  #
  # @!attribute [rw] log_level
  #   @return [Symbol] Log level for rate limit events. Default is :info.
  #     Valid values: :debug, :info, :warn, :error
  #
  # @!attribute [rw] on_callback_error
  #   @return [Proc, nil] Optional callback invoked when a stream callback raises
  #     an exception. The stream continues processing after this callback returns.
  #     Receives a hash with the following keys:
  #     - :error [Exception] - The exception that was raised
  #     - :filing [SecApi::Objects::StreamFiling] - The filing being processed
  #     - :accession_no [String] - SEC accession number
  #     - :ticker [String, nil] - Stock ticker symbol
  #
  #   @example Log to external error service
  #     config = SecApi::Config.new(
  #       api_key: "...",
  #       on_callback_error: ->(info) {
  #         Bugsnag.notify(info[:error], {
  #           filing: info[:accession_no],
  #           ticker: info[:ticker]
  #         })
  #       }
  #     )
  #
  #   @example Custom error handling
  #     config = SecApi::Config.new(
  #       api_key: "...",
  #       on_callback_error: ->(info) {
  #         Rails.logger.error("Stream callback failed: #{info[:error].message}")
  #         ErrorQueue.push(info[:error], info[:filing].to_h)
  #       }
  #     )
  #
  # @!attribute [rw] on_reconnect
  #   @return [Proc, nil] Optional callback invoked when WebSocket reconnection succeeds.
  #     Receives a hash with the following keys:
  #     - :attempt_count [Integer] - Number of reconnection attempts before success
  #     - :downtime_seconds [Float] - Total time disconnected in seconds
  #
  #   @example Track reconnections in metrics
  #     config = SecApi::Config.new(
  #       api_key: "...",
  #       on_reconnect: ->(info) {
  #         StatsD.increment("sec_api.stream.reconnected")
  #         StatsD.gauge("sec_api.stream.downtime", info[:downtime_seconds])
  #       }
  #     )
  #
  # @!attribute [rw] stream_max_reconnect_attempts
  #   @return [Integer] Maximum number of WebSocket reconnection attempts before
  #     giving up and raising ReconnectionError. Default is 10.
  #     Set to 0 to disable auto-reconnect entirely.
  #
  # @!attribute [rw] stream_initial_reconnect_delay
  #   @return [Float] Initial delay in seconds before the first reconnection attempt.
  #     Subsequent attempts use exponential backoff. Default is 1.0 second.
  #
  # @!attribute [rw] stream_max_reconnect_delay
  #   @return [Float] Maximum delay in seconds between reconnection attempts.
  #     Caps the exponential backoff to prevent excessively long waits. Default is 60.0 seconds.
  #
  # @!attribute [rw] stream_backoff_multiplier
  #   @return [Integer, Float] Multiplier for exponential backoff between reconnection
  #     attempts. Delay formula: min(initial * (multiplier ^ attempt), max_delay).
  #     Default is 2 (delays: 1s, 2s, 4s, 8s, ..., capped at max).
  #
  # @!attribute [rw] on_filing
  #   @return [Proc, nil] Optional callback invoked when a filing is received via stream.
  #     Called for ALL filings before filtering and before the user callback. Use for
  #     instrumentation and latency monitoring of the full filing stream.
  #   @example Track filing latency with StatsD
  #     on_filing: ->(filing:, latency_ms:, received_at:) {
  #       StatsD.histogram("sec_api.stream.latency_ms", latency_ms)
  #       StatsD.increment("sec_api.stream.filings_received")
  #     }
  #   @example Log latency with structured logging
  #     on_filing: ->(filing:, latency_ms:, received_at:) {
  #       Rails.logger.info("Filing received", {
  #         ticker: filing.ticker,
  #         form_type: filing.form_type,
  #         latency_ms: latency_ms
  #       })
  #     }
  #
  # @!attribute [rw] stream_latency_warning_threshold
  #   @return [Float] Latency threshold in seconds before logging a warning (default: 120).
  #     When a filing's delivery latency exceeds this threshold, a warning is logged.
  #     Set to 120 seconds (2 minutes) to align with NFR1 requirements.
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
      :queue_wait_warning_threshold,
      :on_retry,
      :on_throttle,
      :on_rate_limit,
      :on_queue,
      :on_dequeue,
      :on_excessive_wait,
      :on_callback_error,
      :on_reconnect,
      :on_filing,
      :logger,
      :log_level,
      :stream_max_reconnect_attempts,
      :stream_initial_reconnect_delay,
      :stream_max_reconnect_delay,
      :stream_backoff_multiplier,
      :stream_latency_warning_threshold

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
      self.queue_wait_warning_threshold ||= 300  # 5 minutes
      self.log_level ||= :info
      # Stream reconnection defaults (Story 6.4)
      self.stream_max_reconnect_attempts ||= 10
      self.stream_initial_reconnect_delay ||= 1.0
      self.stream_max_reconnect_delay ||= 60.0
      self.stream_backoff_multiplier ||= 2
      # Stream latency defaults (Story 6.5)
      self.stream_latency_warning_threshold ||= 120.0
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
