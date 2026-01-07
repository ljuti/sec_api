require "faraday"
require "faraday/retry"

module SecApi
  class Client
    def initialize(config = Config.new)
      @_config = config
      @_config.validate!
      @_rate_limit_tracker = RateLimitTracker.new
    end

    def config
      @_config
    end

    def connection
      @_connection ||= build_connection
    end

    # Returns a fresh Query builder instance for constructing SEC filing searches.
    #
    # Unlike other proxy methods, this returns a NEW instance on each call
    # to ensure query chains start with fresh state.
    #
    # @return [SecApi::Query] Fresh query builder instance
    #
    # @example Each call starts fresh
    #   client.query.ticker("AAPL").search  # Query: "ticker:AAPL"
    #   client.query.ticker("TSLA").search  # Query: "ticker:TSLA" (not "ticker:AAPL AND ticker:TSLA")
    #
    def query
      Query.new(self)
    end

    def extractor
      @_extractor ||= Extractor.new(self)
    end

    def mapping
      @_mapping ||= Mapping.new(self)
    end

    # Returns the XBRL extraction proxy for accessing XBRL-to-JSON conversion functionality.
    #
    # @return [SecApi::Xbrl] XBRL proxy instance with access to client's Faraday connection
    #
    # @example Extract XBRL data from a filing
    #   client = SecApi::Client.new(api_key: "your_api_key")
    #   xbrl_data = client.xbrl.to_json(filing)
    #   xbrl_data.financials[:revenue]  # => 394328000000.0
    #
    def xbrl
      @_xbrl ||= Xbrl.new(self)
    end

    # Returns the Stream proxy for real-time filing notifications via WebSocket.
    #
    # @return [SecApi::Stream] Stream proxy instance for WebSocket subscriptions
    #
    # @example Subscribe to real-time filings
    #   client = SecApi::Client.new
    #   client.stream.subscribe do |filing|
    #     puts "New filing: #{filing.ticker} - #{filing.form_type}"
    #   end
    #
    # @example Close the streaming connection
    #   client.stream.close
    #
    # @note The subscribe method blocks while receiving events.
    #   For non-blocking operation, run in a separate thread.
    #
    def stream
      @_stream ||= Stream.new(self)
    end

    # Returns the current rate limit state from the most recent API response.
    #
    # The state is automatically updated after each API request based on
    # X-RateLimit-* headers returned by sec-api.io.
    #
    # @return [RateLimitState, nil] The current rate limit state, or nil if no
    #   rate limit headers have been received yet
    #
    # @example Check rate limit status after requests
    #   client = SecApi::Client.new
    #   client.query.ticker("AAPL").search
    #
    #   state = client.rate_limit_state
    #   puts "Remaining: #{state.remaining}/#{state.limit}"
    #   puts "Resets at: #{state.reset_at}"
    #
    # @example Proactive throttling based on remaining quota
    #   state = client.rate_limit_state
    #   if state&.percentage_remaining && state.percentage_remaining < 10
    #     # Less than 10% remaining, consider slowing down
    #     sleep(1)
    #   end
    #
    # @example Handle exhausted rate limit
    #   if client.rate_limit_state&.exhausted?
    #     wait_time = client.rate_limit_state.reset_at - Time.now
    #     sleep(wait_time) if wait_time.positive?
    #   end
    #
    def rate_limit_state
      @_rate_limit_tracker.current_state
    end

    # Returns the number of requests currently queued waiting for rate limit reset.
    #
    # When the rate limit is exhausted (remaining = 0), incoming requests are
    # queued until the rate limit window resets. This method returns the current
    # count of waiting requests, useful for monitoring and debugging.
    #
    # @return [Integer] Number of requests currently waiting in queue
    #
    # @example Monitor queue depth
    #   client = SecApi::Client.new
    #   # During heavy load when rate limited:
    #   puts "#{client.queued_requests} requests waiting"
    #
    # @example Logging queue status
    #   config = SecApi::Config.new(
    #     api_key: "...",
    #     on_queue: ->(info) {
    #       puts "Request queued (#{info[:queue_size]} total waiting)"
    #     }
    #   )
    #
    def queued_requests
      @_rate_limit_tracker.queued_count
    end

    # Returns a summary of the current rate limit state for debugging and monitoring.
    #
    # Provides a comprehensive view of the rate limit status in a single method call,
    # useful for debugging, logging, and monitoring dashboards.
    #
    # @return [Hash] Rate limit summary with the following keys:
    #   - :remaining [Integer, nil] - Requests remaining in current window
    #   - :limit [Integer, nil] - Total requests allowed per window
    #   - :percentage [Float, nil] - Percentage of quota remaining (0.0-100.0)
    #   - :reset_at [Time, nil] - When the rate limit window resets
    #   - :queued_count [Integer] - Number of requests currently queued
    #   - :exhausted [Boolean] - True if rate limit is exhausted (remaining = 0)
    #
    # @example Quick debugging
    #   client = SecApi::Client.new
    #   client.query.ticker("AAPL").search
    #
    #   pp client.rate_limit_summary
    #   # => {:remaining=>95, :limit=>100, :percentage=>95.0,
    #   #     :reset_at=>2024-01-15 10:30:00 +0000, :queued_count=>0, :exhausted=>false}
    #
    # @example Health check endpoint
    #   get '/health/rate_limit' do
    #     json client.rate_limit_summary
    #   end
    #
    def rate_limit_summary
      state = rate_limit_state
      {
        remaining: state&.remaining,
        limit: state&.limit,
        percentage: state&.percentage_remaining,
        reset_at: state&.reset_at,
        queued_count: queued_requests,
        exhausted: state&.exhausted? || false
      }
    end

    private

    def build_connection
      Faraday.new(url: @_config.base_url) do |conn|
        # Set API key in Authorization header (redacted from Faraday logs automatically)
        conn.headers["Authorization"] = @_config.api_key
        conn.options.timeout = @_config.request_timeout

        # JSON encoding/decoding
        conn.request :json
        conn.response :json, content_type: /\bjson$/, parser_options: {symbolize_names: true}

        # Retry middleware - positioned BEFORE ErrorHandler to catch HTTP status codes
        # Retries on [429, 500, 502, 503, 504] and Faraday exceptions
        conn.request :retry, retry_options

        # Rate limiter middleware - extracts X-RateLimit-* headers from responses,
        # proactively throttles when approaching rate limits, and queues requests
        # when rate limit is exhausted (remaining = 0).
        # Positioned after Retry to capture final response headers (not intermediate retries)
        # Positioned before ErrorHandler to capture headers even from 429 responses
        conn.use Middleware::RateLimiter,
          state_store: @_rate_limit_tracker,
          threshold: @_config.rate_limit_threshold,
          queue_wait_warning_threshold: @_config.queue_wait_warning_threshold,
          on_throttle: @_config.on_throttle,
          on_queue: @_config.on_queue,
          on_dequeue: @_config.on_dequeue,
          on_excessive_wait: @_config.on_excessive_wait,
          logger: @_config.logger,
          log_level: @_config.log_level

        # Error handler middleware - converts HTTP errors to typed exceptions
        # Positioned AFTER retry so non-retryable errors (401, 404, etc.) fail immediately
        conn.use Middleware::ErrorHandler

        # Connection pool configuration (NFR14: minimum 10 concurrent requests)
        # Note: Net::HTTP adapter uses persistent connections but doesn't expose pool_size config
        # The adapter handles concurrent requests via Ruby's thread-safe HTTP implementation
        conn.adapter Faraday.default_adapter
      end
    end

    # Builds retry configuration options for faraday-retry middleware.
    #
    # The retry middleware handles transient failures with exponential backoff.
    # faraday-retry automatically respects Retry-After headers from 429 responses.
    # When Retry-After is absent but X-RateLimit-Reset is present, the middleware
    # calculates the delay from the reset timestamp.
    #
    # @return [Hash] Configuration options for Faraday::Retry::Middleware
    # @api private
    def retry_options
      {
        max: @_config.retry_max_attempts,
        interval: @_config.retry_initial_delay,
        max_interval: @_config.retry_max_delay,
        backoff_factor: @_config.retry_backoff_factor,
        exceptions: [
          Faraday::TimeoutError,
          Faraday::ConnectionFailed,
          Faraday::SSLError,
          # Catch our typed TransientError exceptions and retry them
          SecApi::TransientError
        ],
        methods: [:get, :post],
        retry_statuses: [429, 500, 502, 503, 504],
        # Custom retry logic for RateLimitError with reset_at timestamp
        # When Retry-After header is absent but X-RateLimit-Reset is present,
        # calculate the delay from the reset timestamp
        retry_if: ->(env, exception) {
          calculate_rate_limit_interval(env, exception)
          true # Always allow retry for transient errors
        },
        retry_block: ->(env:, options:, retry_count:, exception:, will_retry_in:) {
          # Called before EACH retry attempt
          # Invoke on_rate_limit callback for 429 responses
          invoke_on_rate_limit_callback(exception, retry_count, env)

          # Basic logging - users can configure @_config.on_retry callback for custom instrumentation
          if @_config.respond_to?(:on_retry) && @_config.on_retry
            @_config.on_retry.call(env, exception, retry_count)
          end
        }
      }
    end

    # Calculates and sets retry interval based on RateLimitError reset_at.
    #
    # When a RateLimitError has a reset_at timestamp but no retry_after,
    # this method calculates the delay from the reset timestamp and stores
    # it in env[:retry_interval] for the retry middleware to use.
    #
    # @param env [Hash] Faraday request environment
    # @param exception [Exception] The exception that triggered the retry
    # @return [void]
    # @api private
    def calculate_rate_limit_interval(env, exception)
      return unless exception.is_a?(SecApi::RateLimitError)
      return if exception.retry_after # Retry-After takes precedence

      if exception.reset_at
        delay = exception.reset_at - Time.now
        env[:retry_interval] = delay.clamp(1, @_config.retry_max_delay) if delay.positive?
      end
    end

    # Invokes the on_rate_limit callback for RateLimitError exceptions and logs the event.
    #
    # @param exception [Exception] The exception that triggered the retry
    # @param retry_count [Integer] Zero-indexed retry count from faraday-retry
    # @param env [Hash] Faraday request environment containing request_id
    # @return [void]
    # @api private
    def invoke_on_rate_limit_callback(exception, retry_count, env = {})
      return unless exception.is_a?(SecApi::RateLimitError)

      log_rate_limit_exceeded(exception, retry_count, env)

      return unless @_config.respond_to?(:on_rate_limit) && @_config.on_rate_limit

      @_config.on_rate_limit.call({
        retry_after: exception.retry_after,
        reset_at: exception.reset_at,
        attempt: retry_count + 1, # Convert 0-indexed to 1-indexed for user convenience
        request_id: env[:request_id]
      })
    end

    # Logs a 429 rate limit exceeded event with structured data.
    #
    # @param exception [RateLimitError] The rate limit exception
    # @param retry_count [Integer] Zero-indexed retry count
    # @param env [Hash] Faraday request environment
    # @return [void]
    # @api private
    def log_rate_limit_exceeded(exception, retry_count, env)
      return unless @_config.logger

      log_data = {
        event: "secapi.rate_limit.exceeded",
        request_id: env[:request_id],
        retry_after: exception.retry_after,
        reset_at: exception.reset_at&.iso8601,
        attempt: retry_count + 1
      }

      begin
        @_config.logger.send(@_config.log_level) { log_data.to_json }
      rescue
        # Don't let logging errors break the request
      end
    end
  end
end
