# frozen_string_literal: true

module SecApi
  # Raised when sec-api.io rate limit is exceeded (429 Too Many Requests).
  #
  # This is a transient error - the retry middleware will automatically
  # retry the request after waiting for the rate limit to reset.
  #
  # The error includes retry context when available from response headers:
  # - {#retry_after}: Duration to wait (from Retry-After header)
  # - {#reset_at}: Timestamp when rate limit resets (from X-RateLimit-Reset header)
  #
  # @example Handling rate limits
  #   begin
  #     client.query.ticker("AAPL").search
  #   rescue SecApi::RateLimitError => e
  #     # Retries exhausted - rate limit hit repeatedly
  #     logger.warn("Rate limit exceeded: #{e.message}")
  #     if e.retry_after
  #       logger.info("Server suggests waiting #{e.retry_after} seconds")
  #     end
  #     notify_ops_team(e)
  #   end
  #
  # @example Checking reset time
  #   rescue SecApi::RateLimitError => e
  #     if e.reset_at
  #       wait_time = e.reset_at - Time.now
  #       sleep(wait_time) if wait_time.positive?
  #     end
  #
  class RateLimitError < TransientError
    # Duration in seconds to wait before retrying (from Retry-After header).
    # @return [Integer, nil] Seconds to wait, or nil if header was not present
    attr_reader :retry_after

    # Timestamp when the rate limit window resets (from X-RateLimit-Reset header).
    # @return [Time, nil] Reset time, or nil if header was not present
    attr_reader :reset_at

    # Creates a new RateLimitError with optional retry context.
    #
    # @param message [String] Error message describing the rate limit
    # @param retry_after [Integer, nil] Seconds to wait (from Retry-After header)
    # @param reset_at [Time, nil] Timestamp when rate limit resets (from X-RateLimit-Reset header)
    # @param request_id [String, nil] Request correlation ID for tracing
    def initialize(message, retry_after: nil, reset_at: nil, request_id: nil)
      super(message, request_id: request_id)
      @retry_after = retry_after
      @reset_at = reset_at
    end
  end
end
