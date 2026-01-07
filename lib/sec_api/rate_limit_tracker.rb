# frozen_string_literal: true

module SecApi
  # Thread-safe manager for rate limit state and queue tracking.
  #
  # This class provides thread-safe storage and access to rate limit information
  # using a Mutex for synchronization. Each Client instance owns its own tracker,
  # ensuring rate limit state is isolated per-client.
  #
  # The tracker receives updates from the RateLimiter middleware and provides
  # read access to the current state via the Client#rate_limit_state method.
  # It also tracks the number of queued requests waiting for rate limit reset.
  #
  # @example Basic usage
  #   tracker = SecApi::RateLimitTracker.new
  #   tracker.update(limit: 100, remaining: 95, reset_at: Time.now + 60)
  #
  #   state = tracker.current_state
  #   state.limit        # => 100
  #   state.remaining    # => 95
  #   state.available?   # => true
  #
  # @example Thread-safe concurrent access
  #   tracker = SecApi::RateLimitTracker.new
  #
  #   threads = 10.times.map do |i|
  #     Thread.new do
  #       tracker.update(limit: 100, remaining: 100 - i, reset_at: Time.now + 60)
  #       tracker.current_state  # Thread-safe read
  #     end
  #   end
  #   threads.each(&:join)
  #
  # @example Per-client isolation
  #   client1 = SecApi::Client.new
  #   client2 = SecApi::Client.new
  #
  #   # Each client has independent rate limit tracking
  #   client1.rate_limit_state  # Client 1's state
  #   client2.rate_limit_state  # Client 2's state (independent)
  #
  # @see SecApi::RateLimitState Immutable state value object
  # @see SecApi::Middleware::RateLimiter Middleware that updates this tracker
  #
  class RateLimitTracker
    # Creates a new RateLimitTracker instance.
    #
    # @example
    #   tracker = SecApi::RateLimitTracker.new
    #   tracker.current_state  # => nil (no state yet)
    #
    def initialize
      @mutex = Mutex.new
      @state = nil
      @queued_count = 0
    end

    # Updates the rate limit state with new values.
    #
    # Creates a new immutable RateLimitState object with the provided values.
    # This method is thread-safe and can be called concurrently.
    #
    # @param limit [Integer, nil] Total requests allowed per time window
    # @param remaining [Integer, nil] Requests remaining in current window
    # @param reset_at [Time, nil] Time when the limit resets
    # @return [RateLimitState] The newly created state
    #
    # @example
    #   tracker.update(limit: 100, remaining: 95, reset_at: Time.now + 60)
    #
    def update(limit:, remaining:, reset_at:)
      @mutex.synchronize do
        @state = RateLimitState.new(
          limit: limit,
          remaining: remaining,
          reset_at: reset_at
        )
      end
    end

    # Returns the current rate limit state.
    #
    # Returns nil if no rate limit information has been received yet.
    # The returned RateLimitState is immutable and can be safely used
    # outside the mutex lock.
    #
    # @return [RateLimitState, nil] The current state or nil if unknown
    #
    # @example
    #   state = tracker.current_state
    #   if state&.exhausted?
    #     # Handle rate limit exhausted
    #   end
    #
    def current_state
      @mutex.synchronize { @state }
    end

    # Clears the current rate limit state.
    #
    # After calling reset!, current_state will return nil until
    # new rate limit headers are received.
    #
    # @return [void]
    #
    # @example
    #   tracker.update(limit: 100, remaining: 0, reset_at: Time.now)
    #   tracker.reset!
    #   tracker.current_state  # => nil
    #
    def reset!
      @mutex.synchronize { @state = nil }
    end

    # Returns the current count of queued requests.
    #
    # When the rate limit is exhausted (remaining = 0), requests are queued
    # until the rate limit resets. This method returns the current count of
    # waiting requests.
    #
    # @return [Integer] Number of requests currently queued
    #
    # @example
    #   tracker.queued_count  # => 3 (three requests waiting)
    #
    def queued_count
      @mutex.synchronize { @queued_count }
    end

    # Increments the queued request counter.
    #
    # Called by the RateLimiter middleware when a request enters the queue.
    #
    # @return [Integer] The new queued count
    #
    def increment_queued
      @mutex.synchronize do
        @queued_count += 1
      end
    end

    # Decrements the queued request counter.
    #
    # Called by the RateLimiter middleware when a request exits the queue.
    #
    # @return [Integer] The new queued count
    #
    def decrement_queued
      @mutex.synchronize do
        @queued_count = [@queued_count - 1, 0].max
      end
    end
  end
end
