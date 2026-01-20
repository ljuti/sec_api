# frozen_string_literal: true

require "faraday"
require "securerandom"
require "json"

module SecApi
  module Middleware
    # Faraday middleware that extracts rate limit headers from API responses,
    # proactively throttles requests when approaching the rate limit, and
    # queues requests when the rate limit is exhausted.
    #
    # This middleware parses X-RateLimit-* headers from sec-api.io responses
    # and updates a shared state store with the current rate limit information.
    # When the remaining quota drops below a configurable threshold, the middleware
    # will sleep until the rate limit window resets to avoid hitting 429 errors.
    # When remaining reaches 0 (exhausted), requests are queued until reset.
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
      # Header name for total requests allowed per time window.
      # @return [String] lowercase header name
      LIMIT_HEADER = "x-ratelimit-limit"

      # Header name for requests remaining in current window.
      # @return [String] lowercase header name
      REMAINING_HEADER = "x-ratelimit-remaining"

      # Header name for Unix timestamp when the limit resets.
      # @return [String] lowercase header name
      RESET_HEADER = "x-ratelimit-reset"

      # Default throttle threshold (10% remaining).
      # Rationale: 10% provides a safety buffer to avoid hitting 429 while not being overly
      # conservative. At typical sec-api.io limits (~100 req/min), 10% = 10 requests buffer,
      # which handles small bursts. Lower values risk 429s; higher values waste capacity.
      # (Architecture ADR-4: Rate Limiting Strategy)
      DEFAULT_THRESHOLD = 0.1

      # Default warning threshold for excessive wait times (5 minutes).
      # Rationale: 5 minutes is long enough to indicate potential issues (API outage,
      # misconfigured limits) but short enough to be actionable. Matches typical
      # monitoring alert thresholds for request latency.
      DEFAULT_QUEUE_WAIT_WARNING_THRESHOLD = 300

      # Default wait time when rate limit is exhausted but reset_at is unknown (60 seconds).
      # Rationale: sec-api.io rate limit windows are typically 60 seconds. When the API
      # doesn't send X-RateLimit-Reset header, this provides a reasonable fallback that
      # aligns with expected window duration without excessive waiting.
      DEFAULT_QUEUE_WAIT_SECONDS = 60

      # Creates a new RateLimiter middleware instance.
      #
      # @param app [#call] The next middleware in the stack
      # @param options [Hash] Configuration options
      # @option options [RateLimitTracker] :state_store The tracker to update with rate limit info
      # @option options [Float] :threshold (0.1) Throttle when percentage remaining drops below
      #   this value (0.0-1.0). Default is 0.1 (10%).
      # @option options [Proc, nil] :on_throttle Callback invoked when throttling occurs.
      #   Receives a hash with :remaining, :limit, :delay, :reset_at, and :request_id keys.
      # @option options [Proc, nil] :on_queue Callback invoked when a request is queued
      #   due to exhausted rate limit (remaining = 0). Receives a hash with :queue_size,
      #   :wait_time, :reset_at, and :request_id keys.
      # @option options [Integer] :queue_wait_warning_threshold (300) Seconds threshold
      #   for warning about excessive wait times. Default is 300 (5 minutes).
      # @option options [Proc, nil] :on_excessive_wait Callback invoked when wait time
      #   exceeds queue_wait_warning_threshold. Receives a hash with :wait_time,
      #   :threshold, :reset_at, and :request_id keys.
      # @option options [Proc, nil] :on_dequeue Callback invoked when a request exits
      #   the queue (after waiting). Receives a hash with :queue_size, :waited, and :request_id keys.
      # @option options [Logger, nil] :logger Logger instance for structured rate limit logging.
      #   Set to nil (default) to disable logging.
      # @option options [Symbol] :log_level (:info) Log level for rate limit events.
      #
      # @example With custom threshold, callbacks, and logging
      #   tracker = SecApi::RateLimitTracker.new
      #   middleware = SecApi::Middleware::RateLimiter.new(app,
      #     state_store: tracker,
      #     threshold: 0.2,  # Throttle at 20% remaining
      #     on_throttle: ->(info) { puts "Throttling for #{info[:delay]}s" },
      #     on_queue: ->(info) { puts "Request queued, #{info[:queue_size]} waiting" },
      #     on_dequeue: ->(info) { puts "Request dequeued after #{info[:waited]}s" },
      #     on_excessive_wait: ->(info) { puts "Warning: wait time #{info[:wait_time]}s" },
      #     logger: Rails.logger,
      #     log_level: :info
      #   )
      #
      def initialize(app, options = {})
        super(app)
        @state_store = options[:state_store]
        @threshold = options.fetch(:threshold, DEFAULT_THRESHOLD)
        @on_throttle = options[:on_throttle]
        @on_queue = options[:on_queue]
        @on_dequeue = options[:on_dequeue]
        @on_excessive_wait = options[:on_excessive_wait]
        @queue_wait_warning_threshold = options.fetch(
          :queue_wait_warning_threshold,
          DEFAULT_QUEUE_WAIT_WARNING_THRESHOLD
        )
        @logger = options[:logger]
        @log_level = options.fetch(:log_level, :info)
        # Thread-safety design: Mutex + ConditionVariable pattern for efficient blocking.
        # Why not just sleep? Sleep wastes CPU cycles polling. ConditionVariable allows
        # threads to truly wait (zero CPU) until signaled, crucial for high-concurrency
        # workloads (Sidekiq, Puma) where many threads may be rate-limited simultaneously.
        # Why not atomic counters? We need to coordinate multiple operations (check state,
        # increment queue, wait) atomically, which requires a mutex.
        @mutex = Mutex.new
        @condition = ConditionVariable.new
      end

      # Returns the current count of queued (waiting) requests.
      #
      # Delegates to the state store if available, otherwise returns 0.
      #
      # @return [Integer] Number of requests currently waiting for rate limit reset
      def queued_count
        @state_store&.queued_count || 0
      end

      # Processes the request with rate limit queueing, throttling, and header extraction.
      #
      # Before sending the request:
      # 1. Generates a unique request_id (UUID) for tracing across callbacks
      # 2. If rate limit is exhausted (remaining = 0), queues the request until reset
      # 3. Otherwise, checks if below threshold and throttles if needed
      #
      # After the response, extracts rate limit headers to update state.
      #
      # @param env [Faraday::Env] The request/response environment
      # @return [Faraday::Response] The response
      #
      def call(env)
        # Generate unique request_id for tracing across all callbacks
        request_id = env[:request_id] ||= SecureRandom.uuid

        wait_if_exhausted(request_id)
        throttle_if_needed(request_id)

        @app.call(env).on_complete do |response_env|
          extract_rate_limit_headers(response_env)
          signal_waiting_threads
        end
      end

      private

      # Blocks the request if the rate limit is exhausted (remaining = 0).
      #
      # When exhausted, increments the queued count, invokes the on_queue callback,
      # and waits using ConditionVariable until signaled or timeout. Uses a while
      # loop to re-check state after wakeup in case another thread took the slot.
      #
      # Thread-safety: Uses mutex and ConditionVariable for efficient blocking.
      # Sequential release: After reset, threads are signaled one at a time.
      # Exception safety: Uses ensure block to guarantee queued_count is decremented.
      #
      # @param request_id [String] Unique identifier for tracing this request
      # @return [void]
      #
      def wait_if_exhausted(request_id)
        return unless @state_store

        @mutex.synchronize do
          state = @state_store.current_state
          return unless state
          return unless exhausted?(state)

          # Calculate wait time, using default if reset_at is unknown
          wait_time = calculate_delay_with_default(state)
          return unless wait_time.positive?

          queued_at = Time.now
          @state_store.increment_queued
          begin
            invoke_queue_callback(state, wait_time, request_id)
            warn_if_excessive_wait(wait_time, state.reset_at, request_id)

            # Wait using ConditionVariable with timeout.
            # Re-check state after wakeup in while loop - another thread may have taken
            # the available capacity before this thread resumes (spurious wakeup handling).
            # This is the standard pattern for condition variable usage (Mesa semantics).
            while should_wait?
              remaining_wait = calculate_remaining_wait_with_default
              break unless remaining_wait.positive?
              @condition.wait(@mutex, remaining_wait)
            end
          ensure
            @state_store.decrement_queued
            invoke_dequeue_callback(Time.now - queued_at, request_id)
          end
        end
      end

      # Determines if the current thread should continue waiting.
      #
      # Checks if rate limit is still exhausted. Does not check reset_passed
      # because we may be using default wait time when reset_at is nil.
      # Called after ConditionVariable wakeup to re-verify state.
      #
      # @return [Boolean] true if thread should continue waiting
      #
      def should_wait?
        state = @state_store.current_state
        return false unless state
        exhausted?(state)
      end

      # Calculates remaining wait time until reset, with default fallback.
      #
      # When reset_at is nil (API didn't send X-RateLimit-Reset header),
      # returns 0 to allow the wait loop to exit and retry.
      #
      # @return [Float] Seconds remaining until reset, or 0 if unknown/passed
      #
      def calculate_remaining_wait_with_default
        state = @state_store.current_state
        return 0 unless state&.reset_at
        delay = state.reset_at - Time.now
        delay.positive? ? delay : 0
      end

      # Checks if the rate limit is exhausted (remaining = 0).
      #
      # @param state [RateLimitState] The current rate limit state
      # @return [Boolean] true if remaining is exactly 0
      #
      def exhausted?(state)
        state.remaining&.zero?
      end

      # Invokes the on_queue callback if configured and logs the event.
      #
      # @param state [RateLimitState] The current rate limit state
      # @param wait_time [Float] Seconds the request will wait
      # @param request_id [String] Unique identifier for tracing this request
      # @return [void]
      #
      def invoke_queue_callback(state, wait_time, request_id)
        log_queue(state, wait_time, request_id)

        return unless @on_queue

        @on_queue.call(
          queue_size: queued_count,
          wait_time: wait_time,
          reset_at: state.reset_at,
          request_id: request_id
        )
      end

      # Logs a queue event with structured data.
      #
      # @param state [RateLimitState] The current rate limit state
      # @param wait_time [Float] Seconds the request will wait
      # @param request_id [String] Unique identifier for tracing this request
      # @return [void]
      #
      def log_queue(state, wait_time, request_id)
        return unless @logger

        log_event(
          event: "secapi.rate_limit.queue",
          request_id: request_id,
          queue_size: queued_count,
          wait_time: wait_time.round(2),
          reset_at: state.reset_at&.iso8601
        )
      end

      # Invokes the on_dequeue callback if configured.
      #
      # Called when a request exits the queue after waiting.
      #
      # @param waited [Float] Actual seconds the request waited
      # @param request_id [String] Unique identifier for tracing this request
      # @return [void]
      #
      def invoke_dequeue_callback(waited, request_id)
        return unless @on_dequeue

        @on_dequeue.call(
          queue_size: queued_count,
          waited: waited,
          request_id: request_id
        )
      end

      # Calculates delay until reset, using default when reset_at is unknown.
      #
      # When the API returns remaining=0 but no X-RateLimit-Reset header,
      # uses DEFAULT_QUEUE_WAIT_SECONDS (60s) as a fallback.
      #
      # @param state [RateLimitState] The current rate limit state
      # @return [Float] Seconds to wait (always positive when exhausted)
      #
      def calculate_delay_with_default(state)
        if state.reset_at.nil?
          # No reset time known - use default wait
          DEFAULT_QUEUE_WAIT_SECONDS
        else
          delay = state.reset_at - Time.now
          delay.positive? ? delay : 0
        end
      end

      # Warns when wait time exceeds the configured threshold.
      #
      # Invokes the on_excessive_wait callback when the wait time is greater
      # than queue_wait_warning_threshold (default 300 seconds / 5 minutes).
      # The request continues waiting after the warning.
      #
      # @param wait_time [Float] Seconds the request will wait
      # @param reset_at [Time] When the rate limit resets
      # @param request_id [String] Unique identifier for tracing this request
      # @return [void]
      #
      def warn_if_excessive_wait(wait_time, reset_at, request_id)
        return unless wait_time > @queue_wait_warning_threshold
        return unless @on_excessive_wait

        @on_excessive_wait.call(
          wait_time: wait_time,
          threshold: @queue_wait_warning_threshold,
          reset_at: reset_at,
          request_id: request_id
        )
      end

      # Signals waiting threads that the rate limit may have reset.
      #
      # Called after each response to wake up one waiting thread.
      # Uses ConditionVariable for efficient thread coordination.
      #
      # @return [void]
      #
      def signal_waiting_threads
        @mutex.synchronize do
          @condition.signal
        end
      end

      # Checks rate limit state and sleeps if below threshold.
      #
      # Only throttles when:
      # - State store exists
      # - Current state exists (at least one prior response received)
      # - Rate limit is NOT exhausted (remaining > 0) - exhausted case handled by wait_if_exhausted
      # - Reset time has not passed (state is still valid)
      # - Percentage remaining is below threshold
      # - Delay is positive (reset is in the future)
      #
      # @param request_id [String] Unique identifier for tracing this request
      # @return [void]
      #
      def throttle_if_needed(request_id)
        return unless @state_store

        state = @state_store.current_state
        return unless state
        return if exhausted?(state)  # Exhausted case handled separately by queueing
        return if reset_passed?(state)
        return unless should_throttle?(state)

        delay = calculate_delay(state)
        return unless delay.positive?

        invoke_throttle_callback(state, delay, request_id)
        sleep(delay)
      end

      # Invokes the on_throttle callback if configured and logs the event.
      #
      # @param state [RateLimitState] The current rate limit state
      # @param delay [Float] Seconds the request will be delayed
      # @param request_id [String] Unique identifier for tracing this request
      # @return [void]
      #
      def invoke_throttle_callback(state, delay, request_id)
        log_throttle(state, delay, request_id)

        return unless @on_throttle

        @on_throttle.call(
          remaining: state.remaining,
          limit: state.limit,
          delay: delay,
          reset_at: state.reset_at,
          request_id: request_id
        )
      end

      # Logs a throttle event with structured data.
      #
      # @param state [RateLimitState] The current rate limit state
      # @param delay [Float] Seconds the request will be delayed
      # @param request_id [String] Unique identifier for tracing this request
      # @return [void]
      #
      def log_throttle(state, delay, request_id)
        return unless @logger

        log_event(
          event: "secapi.rate_limit.throttle",
          request_id: request_id,
          remaining: state.remaining,
          limit: state.limit,
          delay: delay.round(2),
          reset_at: state.reset_at&.iso8601
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

      # Logs a structured event using the configured logger and log level.
      #
      # Outputs events as JSON for compatibility with monitoring tools
      # like ELK, Splunk, and Datadog.
      #
      # @param data [Hash] Event data to log
      # @return [void]
      #
      def log_event(data)
        return unless @logger

        begin
          @logger.send(@log_level) { data.to_json }
        rescue
          # Don't let logging errors break the request
          # Silently ignore - logging is best-effort
        end
      end
    end
  end
end
