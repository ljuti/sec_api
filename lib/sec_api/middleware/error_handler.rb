# frozen_string_literal: true

require "faraday"

module SecApi
  # Faraday middleware for SEC API operations.
  #
  # These middleware classes handle common concerns like error handling,
  # rate limiting, and instrumentation. They are automatically configured
  # in the Client's Faraday connection.
  #
  # @see SecApi::Middleware::ErrorHandler HTTP error to exception conversion
  # @see SecApi::Middleware::RateLimiter Rate limit tracking and throttling
  # @see SecApi::Middleware::Instrumentation Request/response instrumentation
  #
  module Middleware
    # Faraday middleware that converts HTTP status codes and Faraday exceptions
    # into typed SecApi exceptions.
    #
    # This middleware maps:
    # - HTTP 400 → ValidationError (permanent)
    # - HTTP 401 → AuthenticationError (permanent)
    # - HTTP 403 → AuthenticationError (permanent)
    # - HTTP 404 → NotFoundError (permanent)
    # - HTTP 422 → ValidationError (permanent)
    # - HTTP 429 → RateLimitError (transient)
    # - HTTP 5xx → ServerError (transient)
    # - Faraday::TimeoutError → NetworkError (transient)
    # - Faraday::ConnectionFailed → NetworkError (transient)
    # - Faraday::SSLError → NetworkError (transient)
    #
    # Position in middleware stack: After retry/rate limiter, before adapter
    #
    # @raise [ValidationError] when API returns 400 (Bad Request) or 422 (Unprocessable Entity)
    # @raise [AuthenticationError] when API returns 401 (Unauthorized) or 403 (Forbidden)
    # @raise [NotFoundError] when API returns 404 (Not Found)
    # @raise [RateLimitError] when API returns 429 (Too Many Requests)
    # @raise [ServerError] when API returns 5xx (Server Error)
    # @raise [NetworkError] when network issues occur (timeout, connection failure, SSL error)
    class ErrorHandler < Faraday::Middleware
      # Initializes the error handler middleware.
      #
      # @param app [Faraday::Middleware] The next middleware in the stack
      # @param options [Hash] Configuration options
      # @option options [SecApi::Config] :config The config object containing on_error callback
      def initialize(app, options = {})
        super(app)
        @config = options[:config]
      end

      # Processes the request and converts HTTP errors to typed exceptions.
      #
      # @param env [Faraday::Env] The request/response environment
      # @return [Faraday::Response] The response (if no error)
      # @raise [ValidationError] when API returns 400 or 422
      # @raise [AuthenticationError] when API returns 401 or 403
      # @raise [NotFoundError] when API returns 404
      # @raise [RateLimitError] when API returns 429
      # @raise [ServerError] when API returns 5xx
      # @raise [NetworkError] when network issues occur
      #
      def call(env)
        response = @app.call(env)
        handle_response(response.env)
        response
      rescue Faraday::RetriableResponse => e
        # Faraday retry raises this to signal a retry - we need to re-raise it
        # so retry middleware can catch it
        raise e
      rescue Faraday::TimeoutError => e
        # Don't invoke on_error here - TransientErrors will be retried.
        # on_error is invoked by Instrumentation middleware after all retries exhausted.
        raise NetworkError.new(
          "Request timeout. " \
          "Check network connectivity or increase request_timeout in configuration. " \
          "Original error: #{e.message}.",
          request_id: env[:request_id]
        )
      rescue Faraday::ConnectionFailed => e
        # Don't invoke on_error here - TransientErrors will be retried.
        # on_error is invoked by Instrumentation middleware after all retries exhausted.
        raise NetworkError.new(
          "Connection failed: #{e.message}. " \
          "Verify network connectivity and sec-api.io availability. " \
          "This is a temporary issue that will be retried automatically.",
          request_id: env[:request_id]
        )
      rescue Faraday::SSLError => e
        # Don't invoke on_error here - TransientErrors will be retried.
        # on_error is invoked by Instrumentation middleware after all retries exhausted.
        raise NetworkError.new(
          "SSL/TLS error: #{e.message}. " \
          "This may indicate certificate validation issues or secure connection problems. " \
          "Verify your system's SSL certificates are up to date.",
          request_id: env[:request_id]
        )
      end

      private

      def handle_response(env)
        # Only handle error responses - skip success responses
        return if env[:status] >= 200 && env[:status] < 300

        error = build_error_for_status(env)
        return unless error

        # NOTE: on_error callback is NOT invoked here.
        # All on_error invocations happen in Instrumentation middleware after the exception
        # escapes all middleware (including retry). This ensures on_error is called exactly once,
        # only when the request ultimately fails (after all retries exhausted for TransientError,
        # or immediately for PermanentError).
        raise error
      end

      # Builds the appropriate error for the HTTP status code.
      #
      # Error Taxonomy Decision (Architecture ADR-2):
      # - TransientError (retryable): Network issues, server errors, rate limits - worth retrying
      #   because the underlying issue may resolve. Supports NFR5: 95%+ automatic recovery.
      # - PermanentError (fail-fast): Client errors like auth, validation, not found - no point
      #   retrying because the same request will always fail. Fail immediately to save resources.
      #
      # @param env [Faraday::Env] The response environment
      # @return [SecApi::Error, nil] The appropriate error, or nil for unhandled status
      def build_error_for_status(env)
        request_id = env[:request_id]

        case env[:status]
        # 400/422: PermanentError - Client sent invalid data. Retrying won't help.
        when 400
          ValidationError.new(
            "Bad request (400): The request was malformed or contains invalid parameters. " \
            "Check your query parameters, ticker symbols, or search criteria.",
            request_id: request_id
          )
        # 401/403: PermanentError - Auth issues need human intervention (fix API key or subscription).
        # Both map to AuthenticationError because the resolution is the same: fix credentials.
        when 401
          AuthenticationError.new(
            "API authentication failed (401 Unauthorized). " \
            "Verify your API key in config/secapi.yml or SECAPI_API_KEY environment variable. " \
            "Get your API key from https://sec-api.io.",
            request_id: request_id
          )
        when 403
          AuthenticationError.new(
            "Access forbidden (403): Your API key does not have permission for this resource. " \
            "Verify your subscription plan at https://sec-api.io or contact support.",
            request_id: request_id
          )
        # 404: PermanentError - Resource doesn't exist. Retrying won't create it.
        when 404
          NotFoundError.new(
            "Resource not found (404): #{env[:url]&.path || "unknown"}. " \
            "Check ticker symbol, CIK, or filing identifier.",
            request_id: request_id
          )
        when 422
          ValidationError.new(
            "Unprocessable entity (422): The request was valid but could not be processed. " \
            "This may indicate invalid query logic or unsupported parameter combinations.",
            request_id: request_id
          )
        # 429: TransientError - Rate limit will reset. Worth waiting and retrying automatically.
        # Supports FR5.4: "automatically resume when capacity returns"
        when 429
          retry_after = parse_retry_after(env[:response_headers])
          reset_at = parse_reset_timestamp(env[:response_headers])

          RateLimitError.new(
            build_rate_limit_message(retry_after, reset_at),
            retry_after: retry_after,
            reset_at: reset_at,
            request_id: request_id
          )
        # 5xx: TransientError - Server issues are typically temporary. Retry with backoff.
        # Supports NFR5: 95%+ automatic recovery from transient failures.
        when 500..504
          ServerError.new(
            "sec-api.io server error (#{env[:status]}). " \
            "automatic retry attempts exhausted. This may indicate a prolonged outage.",
            request_id: request_id
          )
        end
      end

      # Parses Retry-After header value (integer seconds or HTTP-date format).
      #
      # @param headers [Hash, nil] Response headers
      # @return [Integer, nil] Seconds to wait, or nil if header not present/invalid
      def parse_retry_after(headers)
        return nil unless headers

        value = headers["Retry-After"] || headers["retry-after"]
        return nil unless value

        # Try integer format first (e.g., "60")
        Integer(value, 10)
      rescue ArgumentError
        # Try HTTP-date format (e.g., "Wed, 07 Jan 2026 12:00:00 GMT")
        begin
          http_date = Time.httpdate(value)
          delay = (http_date - Time.now).to_i
          [delay, 0].max
        rescue ArgumentError
          nil
        end
      end

      # Parses X-RateLimit-Reset header to a Time object.
      #
      # @param headers [Hash, nil] Response headers
      # @return [Time, nil] Reset timestamp, or nil if header not present/invalid
      def parse_reset_timestamp(headers)
        return nil unless headers

        value = headers["X-RateLimit-Reset"] || headers["x-ratelimit-reset"]
        return nil unless value

        Time.at(Integer(value, 10))
      rescue ArgumentError, TypeError
        nil
      end

      # Builds an actionable error message for rate limit errors.
      #
      # @param retry_after [Integer, nil] Seconds to wait
      # @param reset_at [Time, nil] Reset timestamp
      # @return [String] Formatted error message
      def build_rate_limit_message(retry_after, reset_at)
        parts = ["Rate limit exceeded (429 Too Many Requests)."]

        if retry_after
          parts << "Retry after #{retry_after} seconds."
        elsif reset_at
          parts << "Rate limit resets at #{reset_at.utc.strftime("%Y-%m-%d %H:%M:%S UTC")}."
        end

        parts << "Automatic retry attempts exhausted. Consider implementing backoff or reducing request rate."
        parts.join(" ")
      end

      # NOTE: on_error callback is NOT invoked here.
      # All on_error invocations happen in Instrumentation middleware (first in stack)
      # after exceptions escape all middleware (including retry). This ensures on_error
      # is called exactly once, only when the request ultimately fails.
    end
  end
end
