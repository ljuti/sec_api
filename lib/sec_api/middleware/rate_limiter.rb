# frozen_string_literal: true

require "faraday"

module SecApi
  module Middleware
    # Faraday middleware that extracts rate limit headers from API responses
    # and proactively throttles requests when approaching the rate limit.
    #
    # This middleware parses X-RateLimit-* headers from sec-api.io responses
    # and updates a shared state store with the current rate limit information.
    # When the remaining quota drops below a configurable threshold, the middleware
    # will sleep until the rate limit window resets to avoid hitting 429 errors.
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
    #     conn.use SecApi::Middleware::RateLimiter,
    #       state_store: tracker,
    #       threshold: 0.1  # Throttle when < 10% remaining
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

      # Default throttle threshold (10% remaining)
      DEFAULT_THRESHOLD = 0.1

      # Creates a new RateLimiter middleware instance.
      #
      # @param app [#call] The next middleware in the stack
      # @param options [Hash] Configuration options
      # @option options [RateLimitTracker] :state_store The tracker to update with rate limit info
      # @option options [Float] :threshold (0.1) Throttle when percentage remaining drops below
      #   this value (0.0-1.0). Default is 0.1 (10%).
      # @option options [Proc, nil] :on_throttle Callback invoked when throttling occurs.
      #   Receives a hash with :remaining, :limit, :delay, and :reset_at keys.
      #
      # @example With custom threshold and callback
      #   tracker = SecApi::RateLimitTracker.new
      #   middleware = SecApi::Middleware::RateLimiter.new(app,
      #     state_store: tracker,
      #     threshold: 0.2,  # Throttle at 20% remaining
      #     on_throttle: ->(info) { puts "Throttling for #{info[:delay]}s" }
      #   )
      #
      def initialize(app, options = {})
        super(app)
        @state_store = options[:state_store]
        @threshold = options.fetch(:threshold, DEFAULT_THRESHOLD)
        @on_throttle = options[:on_throttle]
      end

      # Processes the request with proactive throttling and header extraction.
      #
      # Before sending the request, checks if rate limit quota is below the
      # configured threshold. If so, sleeps until the reset time to avoid
      # hitting 429 errors. After the response, extracts rate limit headers
      # to update the state for future throttle decisions.
      #
      # @param env [Faraday::Env] The request/response environment
      # @return [Faraday::Response] The response
      #
      def call(env)
        throttle_if_needed

        @app.call(env).on_complete do |response_env|
          extract_rate_limit_headers(response_env)
        end
      end

      private

      # Checks rate limit state and sleeps if below threshold.
      #
      # Only throttles when:
      # - State store exists
      # - Current state exists (at least one prior response received)
      # - Reset time has not passed (state is still valid)
      # - Percentage remaining is below threshold
      # - Delay is positive (reset is in the future)
      #
      # @return [void]
      #
      def throttle_if_needed
        return unless @state_store

        state = @state_store.current_state
        return unless state
        return if reset_passed?(state)
        return unless should_throttle?(state)

        delay = calculate_delay(state)
        return unless delay.positive?

        invoke_throttle_callback(state, delay)
        sleep(delay)
      end

      # Invokes the on_throttle callback if configured.
      #
      # @param state [RateLimitState] The current rate limit state
      # @param delay [Float] Seconds the request will be delayed
      # @return [void]
      #
      def invoke_throttle_callback(state, delay)
        return unless @on_throttle

        @on_throttle.call(
          remaining: state.remaining,
          limit: state.limit,
          delay: delay,
          reset_at: state.reset_at
        )
      end

      # Determines if throttling should be applied based on remaining percentage.
      #
      # @param state [RateLimitState] The current rate limit state
      # @return [Boolean] true if percentage remaining is below threshold
      #
      def should_throttle?(state)
        pct = state.percentage_remaining
        return false if pct.nil?

        # percentage_remaining returns 0.0-100.0, threshold is 0.0-1.0
        # Convert threshold to percentage: 0.1 * 100 = 10%
        pct < (@threshold * 100)
      end

      # Checks if the rate limit window has already reset.
      #
      # @param state [RateLimitState] The current rate limit state
      # @return [Boolean] true if reset_at is nil or in the past
      #
      def reset_passed?(state)
        return true if state.reset_at.nil?
        Time.now >= state.reset_at
      end

      # Calculates the delay in seconds until the rate limit resets.
      #
      # @param state [RateLimitState] The current rate limit state
      # @return [Float] Seconds to wait (0 or positive)
      #
      def calculate_delay(state)
        return 0 if state.reset_at.nil?

        delay = state.reset_at - Time.now
        delay.positive? ? delay : 0
      end

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
