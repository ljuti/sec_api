# frozen_string_literal: true

require "dry-struct"

module SecApi
  # Immutable value object representing rate limit state from sec-api.io response headers.
  #
  # This class uses Dry::Struct for type safety and immutability, ensuring thread-safe
  # access to rate limit information. The state is extracted from HTTP response headers:
  # - X-RateLimit-Limit: Total requests allowed per time window
  # - X-RateLimit-Remaining: Requests remaining in current window
  # - X-RateLimit-Reset: Unix timestamp when the limit resets
  #
  # @example Access rate limit state from client
  #   client = SecApi::Client.new
  #   client.query.ticker("AAPL").search
  #
  #   state = client.rate_limit_state
  #   state.limit        # => 100
  #   state.remaining    # => 95
  #   state.reset_at     # => 2026-01-07 12:00:00 +0000
  #
  # @example Check if rate limit is exhausted
  #   if client.rate_limit_state&.exhausted?
  #     sleep_until(client.rate_limit_state.reset_at)
  #   end
  #
  # @example Calculate percentage remaining for threshold checks
  #   state = client.rate_limit_state
  #   if state&.percentage_remaining && state.percentage_remaining < 10
  #     # Less than 10% remaining, consider throttling
  #   end
  #
  # @see SecApi::RateLimitTracker Thread-safe state storage
  # @see SecApi::Middleware::RateLimiter Middleware that extracts headers
  #
  class RateLimitState < Dry::Struct
    # Transform keys to allow string or symbol input
    transform_keys(&:to_sym)

    # Total requests allowed per time window (from X-RateLimit-Limit header).
    # @return [Integer, nil] The total quota, or nil if header was not present
    attribute? :limit, Types::Coercible::Integer.optional

    # Requests remaining in current time window (from X-RateLimit-Remaining header).
    # @return [Integer, nil] Remaining requests, or nil if header was not present
    attribute? :remaining, Types::Coercible::Integer.optional

    # Time when the rate limit window resets (from X-RateLimit-Reset header).
    # @return [Time, nil] Reset time, or nil if header was not present
    attribute? :reset_at, Types::Strict::Time.optional

    # Checks if the rate limit has been exhausted.
    #
    # Returns true only when we know for certain that remaining requests is zero.
    # Returns false if remaining is unknown (nil) or greater than zero.
    #
    # @return [Boolean] true if remaining requests is exactly 0, false otherwise
    #
    # @example
    #   state = RateLimitState.new(limit: 100, remaining: 0, reset_at: Time.now + 60)
    #   state.exhausted?  # => true
    #
    #   state = RateLimitState.new(limit: 100, remaining: 5, reset_at: Time.now + 60)
    #   state.exhausted?  # => false
    #
    #   state = RateLimitState.new  # No headers received
    #   state.exhausted?  # => false (unknown state, assume available)
    #
    def exhausted?
      remaining == 0
    end

    # Checks if requests are available (not exhausted).
    #
    # Returns true if remaining is greater than zero OR if remaining is unknown.
    # This conservative approach assumes requests are available when state is unknown.
    #
    # @return [Boolean] true if remaining > 0 or remaining is unknown, false if exhausted
    #
    # @example
    #   state = RateLimitState.new(limit: 100, remaining: 5, reset_at: Time.now + 60)
    #   state.available?  # => true
    #
    #   state = RateLimitState.new  # No headers received
    #   state.available?  # => true (unknown state, assume available)
    #
    #   state = RateLimitState.new(limit: 100, remaining: 0, reset_at: Time.now + 60)
    #   state.available?  # => false
    #
    def available?
      !exhausted?
    end

    # Calculates the percentage of rate limit quota remaining.
    #
    # Returns nil if either limit or remaining is unknown, as percentage
    # cannot be calculated without both values.
    #
    # @return [Float, nil] Percentage remaining (0.0 to 100.0), or nil if unknown
    #
    # @example Calculate percentage for threshold checking
    #   state = RateLimitState.new(limit: 100, remaining: 25, reset_at: Time.now + 60)
    #   state.percentage_remaining  # => 25.0
    #
    #   state = RateLimitState.new(limit: 100, remaining: 0, reset_at: Time.now + 60)
    #   state.percentage_remaining  # => 0.0
    #
    # @example Handle unknown state
    #   state = RateLimitState.new  # No headers received
    #   state.percentage_remaining  # => nil
    #
    #   if (pct = state.percentage_remaining) && pct < 10
    #     # Throttle when below 10%
    #   end
    #
    def percentage_remaining
      return nil if limit.nil? || remaining.nil?
      return 0.0 if limit.zero?

      (remaining.to_f / limit * 100).round(1)
    end

    # Override constructor to ensure immutability
    def initialize(attributes = {})
      super
      freeze
    end
  end
end
