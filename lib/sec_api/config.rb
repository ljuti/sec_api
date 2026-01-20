require "anyway_config"

module SecApi
  # Configuration for the SecApi client.
  #
  # Configuration Layering (via anyway_config):
  # Sources are applied in order of increasing precedence:
  # 1. Defaults (defined in initialize method)
  # 2. YAML file (config/secapi.yml)
  # 3. Environment variables (SECAPI_API_KEY, SECAPI_BASE_URL, etc.)
  # Later sources override earlier ones - env vars always win.
  # This allows production deployments to use env vars while keeping
  # YAML for development defaults.
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
  # @!attribute [rw] on_request
  #   @return [Proc, nil] Optional callback invoked BEFORE each REST API request is sent.
  #     Use for request logging, tracing, and custom instrumentation.
  #     Receives a hash with the following keyword arguments:
  #     - :request_id [String] - UUID for correlating this request across all callbacks
  #     - :method [Symbol] - HTTP method (:get, :post, etc.)
  #     - :url [String] - Full request URL
  #     - :headers [Hash] - Request headers (Authorization header is sanitized/excluded)
  #
  #   @example Request logging integration
  #     config = SecApi::Config.new(
  #       api_key: "...",
  #       on_request: ->(request_id:, method:, url:, headers:) {
  #         Rails.logger.info("SEC API Request", {
  #           request_id: request_id,
  #           method: method,
  #           url: url
  #         })
  #       }
  #     )
  #
  #   @example OpenTelemetry tracing integration
  #     config = SecApi::Config.new(
  #       api_key: "...",
  #       on_request: ->(request_id:, method:, url:, headers:) {
  #         span = OpenTelemetry::Trace.current_span
  #         span.set_attribute("sec_api.request_id", request_id)
  #         span.set_attribute("http.method", method.to_s.upcase)
  #         span.set_attribute("http.url", url)
  #       }
  #     )
  #
  # @!attribute [rw] on_response
  #   @return [Proc, nil] Optional callback invoked AFTER each REST API response is received.
  #     Use for response metrics, latency tracking, and observability dashboards.
  #     Receives a hash with the following keyword arguments:
  #     - :request_id [String] - UUID for correlating with the corresponding on_request callback
  #     - :status [Integer] - HTTP status code (200, 429, 500, etc.)
  #     - :duration_ms [Integer] - Request duration in milliseconds
  #     - :url [String] - Request URL
  #     - :method [Symbol] - HTTP method
  #
  #   @example StatsD/Datadog metrics integration
  #     config = SecApi::Config.new(
  #       api_key: "...",
  #       on_response: ->(request_id:, status:, duration_ms:, url:, method:) {
  #         StatsD.histogram("sec_api.request.duration_ms", duration_ms)
  #         StatsD.increment("sec_api.request.#{status >= 400 ? 'error' : 'success'}")
  #       }
  #     )
  #
  #   @example Prometheus metrics integration
  #     config = SecApi::Config.new(
  #       api_key: "...",
  #       on_response: ->(request_id:, status:, duration_ms:, url:, method:) {
  #         SEC_API_REQUEST_DURATION.observe(duration_ms / 1000.0, labels: {method: method, status: status})
  #         SEC_API_REQUESTS_TOTAL.increment(labels: {method: method, status: status})
  #       }
  #     )
  #
  # @!attribute [rw] on_retry
  #   @return [Proc, nil] Optional callback invoked BEFORE each retry attempt for transient errors.
  #     Use for retry monitoring and alerting on degraded API connectivity.
  #     Receives a hash with the following keyword arguments:
  #     - :request_id [String] - UUID for correlating with request/response callbacks
  #     - :attempt [Integer] - Current retry attempt number (1-indexed)
  #     - :max_attempts [Integer] - Maximum retry attempts configured
  #     - :error_class [String] - Name of the exception class that triggered retry
  #     - :error_message [String] - Exception message
  #     - :will_retry_in [Float] - Seconds until retry (from exponential backoff)
  #
  #   @note This callback is distinct from on_error. on_retry fires BEFORE each retry
  #     attempt, while on_error fires on FINAL failure (all retries exhausted).
  #
  #   @example Retry monitoring with StatsD
  #     config = SecApi::Config.new(
  #       api_key: "...",
  #       on_retry: ->(request_id:, attempt:, max_attempts:, error_class:, error_message:, will_retry_in:) {
  #         StatsD.increment("sec_api.retry", tags: ["attempt:#{attempt}", "error:#{error_class}"])
  #         logger.warn("SEC API retry", request_id: request_id, attempt: attempt, error: error_class)
  #       }
  #     )
  #
  #   @example Alert on repeated retries
  #     config = SecApi::Config.new(
  #       api_key: "...",
  #       on_retry: ->(request_id:, attempt:, max_attempts:, error_class:, error_message:, will_retry_in:) {
  #         if attempt >= 3
  #           AlertService.warn("SEC API degraded", {
  #             request_id: request_id,
  #             attempt: attempt,
  #             max_attempts: max_attempts,
  #             error: error_class
  #           })
  #         end
  #       }
  #     )
  #
  # @!attribute [rw] on_error
  #   @return [Proc, nil] Optional callback invoked when a REST API request ultimately fails
  #     (after all retry attempts are exhausted). Use for error tracking and alerting.
  #     Receives a hash with the following keyword arguments:
  #     - :request_id [String] - UUID for correlating with request/response callbacks
  #     - :error [Exception] - The exception that caused the failure
  #     - :url [String] - Request URL
  #     - :method [Symbol] - HTTP method
  #
  #   @note This callback is distinct from on_retry. on_error fires on FINAL failure
  #     (all retries exhausted), while on_retry fires BEFORE each retry attempt.
  #
  #   @example Bugsnag/Sentry error tracking
  #     config = SecApi::Config.new(
  #       api_key: "...",
  #       on_error: ->(request_id:, error:, url:, method:) {
  #         Bugsnag.notify(error, {
  #           request_id: request_id,
  #           url: url,
  #           method: method
  #         })
  #       }
  #     )
  #
  #   @example Custom alerting integration
  #     config = SecApi::Config.new(
  #       api_key: "...",
  #       on_error: ->(request_id:, error:, url:, method:) {
  #         AlertService.send_alert(
  #           severity: error.is_a?(SecApi::PermanentError) ? :high : :medium,
  #           message: "SEC API request failed: #{error.message}",
  #           context: {request_id: request_id, url: url}
  #         )
  #       }
  #     )
  #
  # @!attribute [rw] default_logging
  #   @return [Boolean] When true and logger is configured, automatically sets up
  #     structured logging callbacks for all request lifecycle events using
  #     {SecApi::StructuredLogger}. Default: false.
  #     Explicit callback configurations take precedence over default logging.
  #
  #   @example Enable default structured logging
  #     config = SecApi::Config.new(
  #       api_key: "...",
  #       logger: Rails.logger,
  #       default_logging: true
  #     )
  #     # Logs: secapi.request.start, secapi.request.complete, secapi.request.retry, secapi.request.error
  #
  #   @example Override specific callbacks while using default logging
  #     config = SecApi::Config.new(
  #       api_key: "...",
  #       logger: Rails.logger,
  #       default_logging: true,
  #       on_error: ->(request_id:, error:, url:, method:) {
  #         # Custom error handling takes precedence over default logging
  #         Bugsnag.notify(error)
  #       }
  #     )
  #
  # @!attribute [rw] metrics_backend
  #   @return [Object, nil] Metrics backend instance (StatsD, Datadog::Statsd, etc.).
  #     When configured, automatically sets up metrics callbacks for all operations
  #     using {SecApi::MetricsCollector}. The backend must respond to `increment`,
  #     `histogram`, and/or `gauge` methods. Default: nil.
  #     Explicit callback configurations take precedence over default metrics.
  #
  #   @example StatsD backend
  #     require 'statsd-ruby'
  #     config = SecApi::Config.new(
  #       api_key: "...",
  #       metrics_backend: StatsD.new('localhost', 8125)
  #     )
  #     # Metrics automatically collected: sec_api.requests.*, sec_api.retries.*, etc.
  #
  #   @example Datadog StatsD backend
  #     require 'datadog/statsd'
  #     config = SecApi::Config.new(
  #       api_key: "...",
  #       metrics_backend: Datadog::Statsd.new('localhost', 8125)
  #     )
  #     # Metrics include tags: method, status, error_class, attempt
  #
  #   @example With custom callbacks (metrics_backend + custom on_error)
  #     config = SecApi::Config.new(
  #       api_key: "...",
  #       metrics_backend: statsd,
  #       on_error: ->(request_id:, error:, url:, method:) {
  #         # Custom error handling takes precedence over default metrics
  #         Bugsnag.notify(error)
  #         # You can still call MetricsCollector manually if needed
  #         SecApi::MetricsCollector.record_error(statsd, error_class: error.class.name, method: method)
  #       }
  #     )
  #
  #   @example Combined with default_logging
  #     config = SecApi::Config.new(
  #       api_key: "...",
  #       logger: Rails.logger,
  #       default_logging: true,
  #       metrics_backend: Datadog::Statsd.new('localhost', 8125)
  #     )
  #     # Both logging AND metrics are automatically configured
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
      :on_request,
      :on_response,
      :on_retry,
      :on_error,
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
      :stream_latency_warning_threshold,
      :default_logging,
      :metrics_backend

    # Default values with rationale for each setting.
    # These defaults are chosen to balance reliability with responsiveness.
    def initialize(*)
      super
      self.base_url ||= "https://api.sec-api.io"

      # Retry defaults (NFR5: 95%+ automatic recovery from transient failures)
      # 5 attempts: Empirically provides >95% recovery for typical transient issues.
      # Formula: P(all_fail) = 0.1^5 = 0.00001 (assuming 10% failure rate per attempt)
      self.retry_max_attempts ||= 5
      # 1 second initial delay: Fast enough to feel responsive, slow enough to allow
      # transient issues (network blips, brief overloads) to resolve.
      self.retry_initial_delay ||= 1.0
      # 60 second max delay: Acceptable for backfill/batch operations, prevents
      # excessive delays for interactive use cases.
      self.retry_max_delay ||= 60.0
      # Factor 2: Standard exponential backoff (1s, 2s, 4s, 8s, 16s, 32s, 60s).
      # Doubles each attempt, providing geometric spacing per industry convention.
      self.retry_backoff_factor ||= 2
      self.request_timeout ||= 30

      # Rate limiting defaults (FR5: proactive throttling)
      # 10% threshold: Safety buffer to avoid 429 responses. At 100 req/min limit,
      # this gives ~10 requests buffer. Lower risks 429s; higher wastes capacity.
      self.rate_limit_threshold ||= 0.1
      self.queue_wait_warning_threshold ||= 300  # 5 minutes
      self.log_level ||= :info

      # Stream reconnection defaults (Story 6.4)
      self.stream_max_reconnect_attempts ||= 10
      self.stream_initial_reconnect_delay ||= 1.0
      self.stream_max_reconnect_delay ||= 60.0
      self.stream_backoff_multiplier ||= 2
      # Stream latency defaults (Story 6.5 / NFR1: <2 minute delivery)
      self.stream_latency_warning_threshold ||= 120.0
      # Structured logging defaults (Story 7.3)
      self.default_logging = false if default_logging.nil?
    end

    # Validates configuration and raises ConfigurationError for invalid values.
    # Called automatically during Client initialization.
    #
    # Validation philosophy: Fail fast with actionable error messages.
    # Invalid config should never reach the API - catch it at startup.
    #
    # @raise [ConfigurationError] if any configuration value is invalid
    # @return [void]
    def validate!
      # API key validation: Reject nil, empty, and obviously invalid keys.
      # Why check length < 10? Real sec-api.io keys are ~40 chars. Short strings
      # are likely test values or typos that would cause confusing 401 errors.
      if api_key.nil? || api_key.empty?
        raise ConfigurationError, missing_api_key_message
      end

      # Reject placeholder values that users copy from documentation.
      # Better to fail here with clear message than get cryptic 401 from API.
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
