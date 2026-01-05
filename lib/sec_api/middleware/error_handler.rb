# frozen_string_literal: true

require "faraday"

module SecApi
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
      def call(env)
        @app.call(env).on_complete do |response_env|
          handle_response(response_env)
        end
      rescue Faraday::TimeoutError => e
        raise NetworkError,
          "Request timeout. " \
          "Check network connectivity or increase request_timeout in configuration. " \
          "Original error: #{e.message}."
      rescue Faraday::ConnectionFailed => e
        raise NetworkError,
          "Connection failed: #{e.message}. " \
          "Verify network connectivity and sec-api.io availability. " \
          "This is a temporary issue that will be retried automatically."
      rescue Faraday::SSLError => e
        raise NetworkError,
          "SSL/TLS error: #{e.message}. " \
          "This may indicate certificate validation issues or secure connection problems. " \
          "Verify your system's SSL certificates are up to date."
      end

      private

      def handle_response(env)
        case env[:status]
        when 400
          raise ValidationError,
            "Bad request (400): The request was malformed or contains invalid parameters. " \
            "Check your query parameters, ticker symbols, or search criteria."
        when 401
          raise AuthenticationError,
            "API authentication failed (401 Unauthorized). " \
            "Verify your API key in config/secapi.yml or SECAPI_API_KEY environment variable. " \
            "Get your API key from https://sec-api.io."
        when 403
          raise AuthenticationError,
            "Access forbidden (403): Your API key does not have permission for this resource. " \
            "Verify your subscription plan at https://sec-api.io or contact support."
        when 404
          raise NotFoundError,
            "Resource not found (404): #{env[:url]&.path || 'unknown'}. " \
            "Check ticker symbol, CIK, or filing identifier."
        when 422
          raise ValidationError,
            "Unprocessable entity (422): The request was valid but could not be processed. " \
            "This may indicate invalid query logic or unsupported parameter combinations."
        when 429
          rate_limit_reset = env[:response_headers]&.[]('X-RateLimit-Reset') || env[:response_headers]&.[]('x-ratelimit-reset')
          reset_info = rate_limit_reset ? "Reset at: #{rate_limit_reset}. " : ""
          raise RateLimitError,
            "Rate limit exceeded (429 Too Many Requests). " \
            "#{reset_info}" \
            "Will be automatically retried when retry middleware is configured (Story 1.3)."
        when 500..504
          raise ServerError,
            "sec-api.io server error (#{env[:status]}). " \
            "This is a temporary issue that will be automatically retried when retry middleware is configured (Story 1.3)."
        end
      end
    end
  end
end
