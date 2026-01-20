# frozen_string_literal: true

module SecApi
  # Provides centralized metric recording for SEC API operations.
  #
  # This module standardizes metric names and tags across all integrations.
  # Use directly with your metrics backend, or configure via `metrics_backend`
  # for automatic metrics collection.
  #
  # All metric methods are safe to call - they will not raise exceptions even
  # if the backend is nil, misconfigured, or raises errors. This ensures that
  # metrics never break production operations.
  #
  # @example Direct usage with StatsD
  #   statsd = Datadog::Statsd.new('localhost', 8125)
  #
  #   config.on_response = ->(request_id:, status:, duration_ms:, url:, method:) {
  #     SecApi::MetricsCollector.record_response(statsd,
  #       status: status,
  #       duration_ms: duration_ms,
  #       method: method
  #     )
  #   }
  #
  # @example Automatic metrics with metrics_backend
  #   config = SecApi::Config.new(
  #     api_key: "...",
  #     metrics_backend: Datadog::Statsd.new('localhost', 8125)
  #   )
  #   # Metrics automatically collected for all operations
  #
  # @example New Relic custom events
  #   config.on_response = ->(request_id:, status:, duration_ms:, url:, method:) {
  #     NewRelic::Agent.record_custom_event("SecApiRequest", {
  #       request_id: request_id,
  #       status: status,
  #       duration_ms: duration_ms,
  #       method: method.to_s.upcase
  #     })
  #   }
  #
  # @example Datadog APM integration
  #   config.on_request = ->(request_id:, method:, url:, headers:) {
  #     Datadog::Tracing.trace('sec_api.request') do |span|
  #       span.set_tag('request_id', request_id)
  #       span.set_tag('http.method', method.to_s.upcase)
  #       span.set_tag('http.url', url)
  #     end
  #   }
  #
  # @example OpenTelemetry spans
  #   tracer = OpenTelemetry.tracer_provider.tracer('sec_api')
  #
  #   config.on_request = ->(request_id:, method:, url:, headers:) {
  #     tracer.in_span('sec_api.request', attributes: {
  #       'sec_api.request_id' => request_id,
  #       'http.method' => method.to_s.upcase,
  #       'http.url' => url
  #     }) { }
  #   }
  #
  # @example Prometheus push gateway
  #   prometheus = Prometheus::Client.registry
  #   requests_total = prometheus.counter(:sec_api_requests_total, labels: [:method, :status])
  #   duration_histogram = prometheus.histogram(:sec_api_request_duration_seconds, labels: [:method])
  #
  #   config.on_response = ->(request_id:, status:, duration_ms:, url:, method:) {
  #     requests_total.increment(labels: {method: method.to_s.upcase, status: status.to_s})
  #     duration_histogram.observe(duration_ms / 1000.0, labels: {method: method.to_s.upcase})
  #   }
  #
  module MetricsCollector
    extend self

    # Metric name for total requests made (counter).
    # @return [String] metric name
    REQUESTS_TOTAL = "sec_api.requests.total"

    # Metric name for successful requests (counter, status < 400).
    # @return [String] metric name
    REQUESTS_SUCCESS = "sec_api.requests.success"

    # Metric name for error requests (counter, status >= 400).
    # @return [String] metric name
    REQUESTS_ERROR = "sec_api.requests.error"

    # Metric name for request duration (histogram, milliseconds).
    # @return [String] metric name
    REQUESTS_DURATION = "sec_api.requests.duration_ms"

    # Metric name for retry attempts (counter).
    # @return [String] metric name
    RETRIES_TOTAL = "sec_api.retries.total"

    # Metric name for exhausted retries (counter).
    # @return [String] metric name
    RETRIES_EXHAUSTED = "sec_api.retries.exhausted"

    # Metric name for rate limit hits (counter, 429 responses).
    # @return [String] metric name
    RATE_LIMIT_HIT = "sec_api.rate_limit.hit"

    # Metric name for proactive throttling events (counter).
    # @return [String] metric name
    RATE_LIMIT_THROTTLE = "sec_api.rate_limit.throttle"

    # Metric name for streaming filings received (counter).
    # @return [String] metric name
    STREAM_FILINGS = "sec_api.stream.filings"

    # Metric name for streaming delivery latency (histogram, milliseconds).
    # @return [String] metric name
    STREAM_LATENCY = "sec_api.stream.latency_ms"

    # Metric name for stream reconnection events (counter).
    # @return [String] metric name
    STREAM_RECONNECTS = "sec_api.stream.reconnects"

    # Metric name for filing journey stage duration (histogram, milliseconds).
    # @return [String] metric name
    JOURNEY_STAGE_DURATION = "sec_api.filing.journey.stage_ms"

    # Metric name for total filing journey duration (histogram, milliseconds).
    # @return [String] metric name
    JOURNEY_TOTAL_DURATION = "sec_api.filing.journey.total_ms"

    # Records a successful or failed response.
    #
    # Increments request counters and records duration histogram.
    # Status codes < 400 are considered successful, >= 400 are errors.
    #
    # @param backend [Object] Metrics backend (StatsD, Datadog::Statsd, etc.)
    # @param status [Integer] HTTP status code
    # @param duration_ms [Integer] Request duration in milliseconds
    # @param method [Symbol] HTTP method (:get, :post, etc.)
    # @return [void]
    #
    # @example Record a successful response
    #   MetricsCollector.record_response(statsd, status: 200, duration_ms: 150, method: :get)
    #
    # @example Record an error response
    #   MetricsCollector.record_response(statsd, status: 429, duration_ms: 50, method: :get)
    #
    def record_response(backend, status:, duration_ms:, method:)
      tags = {method: method.to_s.upcase, status: status.to_s}

      increment(backend, REQUESTS_TOTAL, tags: tags)

      if status < 400
        increment(backend, REQUESTS_SUCCESS, tags: tags)
      else
        increment(backend, REQUESTS_ERROR, tags: tags)
      end

      histogram(backend, REQUESTS_DURATION, duration_ms, tags: tags)
    end

    # Records a retry attempt.
    #
    # @param backend [Object] Metrics backend
    # @param attempt [Integer] Retry attempt number (1-indexed)
    # @param error_class [String] Exception class name that triggered retry
    # @return [void]
    #
    # @example Record a retry attempt
    #   MetricsCollector.record_retry(statsd, attempt: 1, error_class: "SecApi::NetworkError")
    #
    def record_retry(backend, attempt:, error_class:)
      tags = {attempt: attempt.to_s, error_class: error_class}
      increment(backend, RETRIES_TOTAL, tags: tags)
    end

    # Records a final error (all retries exhausted).
    #
    # @param backend [Object] Metrics backend
    # @param error_class [String] Exception class name
    # @param method [Symbol] HTTP method
    # @return [void]
    #
    # @example Record a final error
    #   MetricsCollector.record_error(statsd, error_class: "SecApi::NetworkError", method: :get)
    #
    def record_error(backend, error_class:, method:)
      tags = {error_class: error_class, method: method.to_s.upcase}
      increment(backend, RETRIES_EXHAUSTED, tags: tags)
    end

    # Records a rate limit (429) response.
    #
    # @param backend [Object] Metrics backend
    # @param retry_after [Integer, nil] Seconds to wait before retry
    # @return [void]
    #
    # @example Record a rate limit hit
    #   MetricsCollector.record_rate_limit(statsd, retry_after: 30)
    #
    def record_rate_limit(backend, retry_after: nil)
      increment(backend, RATE_LIMIT_HIT)
      gauge(backend, "sec_api.rate_limit.retry_after", retry_after) if retry_after
    end

    # Records proactive throttling.
    #
    # Called when the rate limiter proactively delays a request to avoid
    # hitting the rate limit.
    #
    # @param backend [Object] Metrics backend
    # @param remaining [Integer] Requests remaining before limit
    # @param delay [Float] Seconds the request was delayed
    # @return [void]
    #
    # @example Record proactive throttling
    #   MetricsCollector.record_throttle(statsd, remaining: 5, delay: 1.5)
    #
    def record_throttle(backend, remaining:, delay:)
      increment(backend, RATE_LIMIT_THROTTLE)
      gauge(backend, "sec_api.rate_limit.remaining", remaining)
      histogram(backend, "sec_api.rate_limit.delay_ms", (delay * 1000).round)
    end

    # Records a streaming filing received.
    #
    # @param backend [Object] Metrics backend
    # @param latency_ms [Integer] Filing delivery latency in milliseconds
    # @param form_type [String] Filing form type (10-K, 8-K, etc.)
    # @return [void]
    #
    # @example Record a filing receipt
    #   MetricsCollector.record_filing(statsd, latency_ms: 500, form_type: "10-K")
    #
    def record_filing(backend, latency_ms:, form_type:)
      tags = {form_type: form_type}
      increment(backend, STREAM_FILINGS, tags: tags)
      histogram(backend, STREAM_LATENCY, latency_ms, tags: tags)
    end

    # Records a stream reconnection.
    #
    # @param backend [Object] Metrics backend
    # @param attempt_count [Integer] Number of reconnection attempts
    # @param downtime_seconds [Float] Total downtime in seconds
    # @return [void]
    #
    # @example Record a reconnection
    #   MetricsCollector.record_reconnect(statsd, attempt_count: 3, downtime_seconds: 15.5)
    #
    def record_reconnect(backend, attempt_count:, downtime_seconds:)
      increment(backend, STREAM_RECONNECTS)
      gauge(backend, "sec_api.stream.reconnect_attempts", attempt_count)
      histogram(backend, "sec_api.stream.downtime_ms", (downtime_seconds * 1000).round)
    end

    # Records a filing journey stage completion.
    #
    # Use this to track duration of individual pipeline stages (detected,
    # queried, extracted, processed). Combined with FilingJourney logging,
    # this provides both detailed logs and aggregated metrics.
    #
    # @param backend [Object] Metrics backend
    # @param stage [String] Journey stage (detected, queried, extracted, processed)
    # @param duration_ms [Integer] Stage duration in milliseconds
    # @param form_type [String, nil] Filing form type (10-K, 8-K, etc.)
    # @return [void]
    #
    # @example Record a query stage
    #   MetricsCollector.record_journey_stage(statsd,
    #     stage: "queried",
    #     duration_ms: 150,
    #     form_type: "10-K"
    #   )
    #
    # @see FilingJourney
    #
    def record_journey_stage(backend, stage:, duration_ms:, form_type: nil)
      tags = {stage: stage}
      tags[:form_type] = form_type if form_type
      histogram(backend, JOURNEY_STAGE_DURATION, duration_ms, tags: tags)
    end

    # Records total filing journey duration.
    #
    # Use this to track end-to-end pipeline latency from filing detection
    # through processing completion. Useful for monitoring SLAs and
    # identifying slow pipelines.
    #
    # @param backend [Object] Metrics backend
    # @param total_ms [Integer] Total pipeline duration in milliseconds
    # @param form_type [String, nil] Filing form type (10-K, 8-K, etc.)
    # @param success [Boolean] Whether processing succeeded (default: true)
    # @return [void]
    #
    # @example Record successful pipeline
    #   MetricsCollector.record_journey_total(statsd,
    #     total_ms: 5000,
    #     form_type: "10-K",
    #     success: true
    #   )
    #
    # @example Record failed pipeline
    #   MetricsCollector.record_journey_total(statsd,
    #     total_ms: 500,
    #     form_type: "10-K",
    #     success: false
    #   )
    #
    # @see FilingJourney
    #
    def record_journey_total(backend, total_ms:, form_type: nil, success: true)
      tags = {success: success.to_s}
      tags[:form_type] = form_type if form_type
      histogram(backend, JOURNEY_TOTAL_DURATION, total_ms, tags: tags)
    end

    private

    # Increment a counter metric.
    #
    # Supports both statsd-ruby (no tags) and dogstatsd-ruby (with tags) interfaces.
    # Falls back to no-tag call if backend doesn't support tags.
    #
    # @param backend [Object] Metrics backend
    # @param metric [String] Metric name
    # @param tags [Hash] Tags to include (optional)
    # @return [void]
    # @api private
    def increment(backend, metric, tags: {})
      return unless backend
      return unless backend.respond_to?(:increment)

      if tags.any? && supports_tags?(backend, :increment)
        backend.increment(metric, tags: format_tags(tags))
      else
        backend.increment(metric)
      end
    rescue
      # Don't let metrics errors break operations
    end

    # Record a histogram/timing metric.
    #
    # Falls back to timing method if histogram is not available.
    #
    # @param backend [Object] Metrics backend
    # @param metric [String] Metric name
    # @param value [Numeric] Value to record
    # @param tags [Hash] Tags to include (optional)
    # @return [void]
    # @api private
    def histogram(backend, metric, value, tags: {})
      return unless backend

      if backend.respond_to?(:histogram)
        if tags.any? && supports_tags?(backend, :histogram)
          backend.histogram(metric, value, tags: format_tags(tags))
        else
          backend.histogram(metric, value)
        end
      elsif backend.respond_to?(:timing)
        backend.timing(metric, value)
      end
    rescue
      # Don't let metrics errors break operations
    end

    # Record a gauge metric.
    #
    # @param backend [Object] Metrics backend
    # @param metric [String] Metric name
    # @param value [Numeric] Value to record
    # @param tags [Hash] Tags to include (optional)
    # @return [void]
    # @api private
    def gauge(backend, metric, value, tags: {})
      return unless backend
      return unless backend.respond_to?(:gauge)

      if tags.any? && supports_tags?(backend, :gauge)
        backend.gauge(metric, value, tags: format_tags(tags))
      else
        backend.gauge(metric, value)
      end
    rescue
      # Don't let metrics errors break operations
    end

    # Check if backend method supports tags (arity > minimum required args).
    #
    # @param backend [Object] Metrics backend
    # @param method_name [Symbol] Method name to check
    # @return [Boolean] True if tags are supported
    # @api private
    def supports_tags?(backend, method_name)
      method = backend.method(method_name)
      # arity of -1 or -2 means variable args (accepts keyword args)
      # arity of 1 means only the metric name (no tags)
      # arity of 2 means metric + value (no tags)
      method.arity < 0 || method.arity > 2
    rescue
      false
    end

    # Format tags hash as array of "key:value" strings for StatsD/Datadog.
    #
    # @param tags [Hash] Tags hash
    # @return [Array<String>] Formatted tags
    # @api private
    def format_tags(tags)
      tags.map { |k, v| "#{k}:#{v}" }
    end
  end
end
