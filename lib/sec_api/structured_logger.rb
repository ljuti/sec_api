# frozen_string_literal: true

module SecApi
  # Provides structured JSON logging for SEC API operations.
  #
  # This module can be used directly or via the `default_logging` config option.
  # All log events follow the `secapi.*` naming convention for easy filtering
  # in log aggregation tools like ELK, Datadog, Splunk, or CloudWatch.
  #
  # @example Manual usage with Rails logger
  #   SecApi::StructuredLogger.log_request(Rails.logger, :info,
  #     request_id: "abc-123",
  #     method: :get,
  #     url: "https://api.sec-api.io/query"
  #   )
  #
  # @example Using with default_logging
  #   config = SecApi::Config.new(
  #     api_key: "...",
  #     logger: Rails.logger,
  #     default_logging: true
  #   )
  #   # All requests/responses now logged automatically
  #
  # @example ELK Stack integration
  #   # Configure Logstash to parse JSON logs:
  #   # filter {
  #   #   json { source => "message" }
  #   # }
  #   # Query in Kibana: event:"secapi.request.complete" AND status:>=400
  #
  # @example Datadog Logs integration
  #   # Logs are automatically parsed as JSON by Datadog
  #   # Create facets on: event, request_id, status, duration_ms
  #   # Alert query: event:secapi.request.error count:>10
  #
  # @example Splunk integration
  #   # Search: sourcetype=ruby_json event="secapi.request.*"
  #   # | stats avg(duration_ms) by method
  #
  # @example CloudWatch Logs integration
  #   # Filter pattern: { $.event = "secapi.request.error" }
  #   # Metric filter: Count errors by request_id
  #
  module StructuredLogger
    extend self

    # Logs a request start event.
    #
    # @param logger [Logger] Logger instance (Ruby Logger or compatible interface)
    # @param level [Symbol] Log level (:debug, :info, :warn, :error)
    # @param request_id [String] Request correlation ID (UUID)
    # @param method [Symbol] HTTP method (:get, :post, etc.)
    # @param url [String] Request URL
    # @return [void]
    #
    # @example Basic request logging
    #   SecApi::StructuredLogger.log_request(logger, :info,
    #     request_id: "550e8400-e29b-41d4-a716-446655440000",
    #     method: :get,
    #     url: "https://api.sec-api.io/query"
    #   )
    #   # Output: {"event":"secapi.request.start","request_id":"550e8400-...","method":"GET","url":"https://...","timestamp":"2024-01-15T10:30:00.123Z"}
    #
    def log_request(logger, level, request_id:, method:, url:)
      log_event(logger, level, {
        event: "secapi.request.start",
        request_id: request_id,
        method: method.to_s.upcase,
        url: url,
        timestamp: timestamp
      })
    end

    # Logs a request completion event.
    #
    # @param logger [Logger] Logger instance
    # @param level [Symbol] Log level (:debug, :info, :warn, :error)
    # @param request_id [String] Request correlation ID (matches on_request)
    # @param status [Integer] HTTP status code (200, 429, 500, etc.)
    # @param duration_ms [Integer, Float] Request duration in milliseconds
    # @param url [String] Request URL
    # @param method [Symbol] HTTP method
    # @return [void]
    #
    # @example Response logging with duration
    #   SecApi::StructuredLogger.log_response(logger, :info,
    #     request_id: "550e8400-e29b-41d4-a716-446655440000",
    #     status: 200,
    #     duration_ms: 150,
    #     url: "https://api.sec-api.io/query",
    #     method: :get
    #   )
    #   # Output: {"event":"secapi.request.complete","request_id":"550e8400-...","status":200,"duration_ms":150,"success":true,...}
    #
    def log_response(logger, level, request_id:, status:, duration_ms:, url:, method:)
      log_event(logger, level, {
        event: "secapi.request.complete",
        request_id: request_id,
        status: status,
        duration_ms: duration_ms,
        method: method.to_s.upcase,
        url: url,
        success: status < 400,
        timestamp: timestamp
      })
    end

    # Logs a retry attempt event.
    #
    # @param logger [Logger] Logger instance
    # @param level [Symbol] Log level (typically :warn)
    # @param request_id [String] Request correlation ID
    # @param attempt [Integer] Retry attempt number (1-indexed)
    # @param max_attempts [Integer] Maximum retry attempts configured
    # @param error_class [String] Exception class name that triggered retry
    # @param error_message [String] Exception message
    # @param will_retry_in [Float] Seconds until next retry attempt
    # @return [void]
    #
    # @example Retry logging
    #   SecApi::StructuredLogger.log_retry(logger, :warn,
    #     request_id: "550e8400-e29b-41d4-a716-446655440000",
    #     attempt: 2,
    #     max_attempts: 5,
    #     error_class: "SecApi::ServerError",
    #     error_message: "Internal Server Error",
    #     will_retry_in: 4.0
    #   )
    #   # Output: {"event":"secapi.request.retry","request_id":"550e8400-...","attempt":2,"max_attempts":5,...}
    #
    def log_retry(logger, level, request_id:, attempt:, max_attempts:, error_class:, error_message:, will_retry_in:)
      log_event(logger, level, {
        event: "secapi.request.retry",
        request_id: request_id,
        attempt: attempt,
        max_attempts: max_attempts,
        error_class: error_class,
        error_message: error_message,
        will_retry_in: will_retry_in,
        timestamp: timestamp
      })
    end

    # Logs a request error event (final failure after all retries).
    #
    # @param logger [Logger] Logger instance
    # @param level [Symbol] Log level (typically :error)
    # @param request_id [String] Request correlation ID
    # @param error [Exception] The exception that caused failure
    # @param url [String] Request URL
    # @param method [Symbol] HTTP method
    # @return [void]
    #
    # @example Error logging
    #   SecApi::StructuredLogger.log_error(logger, :error,
    #     request_id: "550e8400-e29b-41d4-a716-446655440000",
    #     error: SecApi::AuthenticationError.new("Invalid API key"),
    #     url: "https://api.sec-api.io/query",
    #     method: :get
    #   )
    #   # Output: {"event":"secapi.request.error","request_id":"550e8400-...","error_class":"SecApi::AuthenticationError",...}
    #
    def log_error(logger, level, request_id:, error:, url:, method:)
      log_event(logger, level, {
        event: "secapi.request.error",
        request_id: request_id,
        error_class: error.class.name,
        error_message: error.message,
        method: method.to_s.upcase,
        url: url,
        timestamp: timestamp
      })
    end

    private

    # Writes a structured log event to the logger.
    #
    # @param logger [Logger] Logger instance
    # @param level [Symbol] Log level
    # @param data [Hash] Event data to serialize as JSON
    # @return [void]
    # @api private
    def log_event(logger, level, data)
      logger.send(level) { data.to_json }
    rescue
      # Don't let logging errors break the request flow
    end

    # Returns current UTC timestamp in ISO8601 format with milliseconds.
    #
    # @return [String] ISO8601 timestamp (e.g., "2024-01-15T10:30:00.123Z")
    # @api private
    def timestamp
      Time.now.utc.iso8601(3)
    end
  end
end
