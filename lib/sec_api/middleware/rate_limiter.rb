# frozen_string_literal: true

require "faraday"

module SecApi
  module Middleware
    # Faraday middleware that extracts rate limit headers from API responses.
    #
    # This middleware parses X-RateLimit-* headers from sec-api.io responses
    # and updates a shared state store with the current rate limit information.
    #
    # Headers parsed:
    # - X-RateLimit-Limit: Total requests allowed per time window
    # - X-RateLimit-Remaining: Requests remaining in current window
    # - X-RateLimit-Reset: Unix timestamp when the limit resets
    #
    # Position in middleware stack: After Retry, before ErrorHandler
    # This ensures we capture headers from the final response (after retries)
    # and can extract rate limit info even from error responses (429).
    #
    # @example Middleware stack integration
    #   Faraday.new(url: base_url) do |conn|
    #     conn.request :retry, retry_options
    #     conn.use SecApi::Middleware::RateLimiter, state_store: tracker
    #     conn.use SecApi::Middleware::ErrorHandler
    #     conn.adapter Faraday.default_adapter
    #   end
    #
    # @see SecApi::RateLimitTracker Thread-safe state storage
    # @see SecApi::RateLimitState Immutable state value object
    #
    class RateLimiter < Faraday::Middleware
      # Header names (Faraday normalizes to lowercase)
      LIMIT_HEADER = "x-ratelimit-limit"
      REMAINING_HEADER = "x-ratelimit-remaining"
      RESET_HEADER = "x-ratelimit-reset"

      # Creates a new RateLimiter middleware instance.
      #
      # @param app [#call] The next middleware in the stack
      # @param options [Hash] Configuration options
      # @option options [RateLimitTracker] :state_store The tracker to update with rate limit info
      #
      # @example
      #   tracker = SecApi::RateLimitTracker.new
      #   middleware = SecApi::Middleware::RateLimiter.new(app, state_store: tracker)
      #
      def initialize(app, options = {})
        super(app)
        @state_store = options[:state_store]
      end

      # Processes the request and extracts rate limit headers from the response.
      #
      # @param env [Faraday::Env] The request/response environment
      # @return [Faraday::Response] The response
      #
      def call(env)
        @app.call(env).on_complete do |response_env|
          extract_rate_limit_headers(response_env)
        end
      end

      private

      # Extracts rate limit headers and updates the state store.
      #
      # Only updates state if at least one rate limit header is present.
      # Missing headers result in nil values for those fields.
      #
      # @param env [Faraday::Env] The response environment
      #
      def extract_rate_limit_headers(env)
        return unless @state_store

        headers = env[:response_headers]
        return unless headers

        limit = parse_integer(headers[LIMIT_HEADER])
        remaining = parse_integer(headers[REMAINING_HEADER])
        reset_at = parse_timestamp(headers[RESET_HEADER])

        # Only update if we got at least one header
        return if limit.nil? && remaining.nil? && reset_at.nil?

        @state_store.update(
          limit: limit,
          remaining: remaining,
          reset_at: reset_at
        )
      end

      # Parses a header value as an integer.
      #
      # @param value [String, nil] The header value
      # @return [Integer, nil] The parsed integer or nil
      #
      def parse_integer(value)
        return nil if value.nil? || value.to_s.empty?
        Integer(value)
      rescue ArgumentError, TypeError
        nil
      end

      # Parses a Unix timestamp header value as a Time object.
      #
      # @param value [String, nil] The Unix timestamp header value
      # @return [Time, nil] The parsed Time object or nil
      #
      def parse_timestamp(value)
        return nil if value.nil? || value.to_s.empty?
        Time.at(Integer(value))
      rescue ArgumentError, TypeError
        nil
      end
    end
  end
end
