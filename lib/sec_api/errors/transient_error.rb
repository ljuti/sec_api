# frozen_string_literal: true

module SecApi
  # Base class for all retryable (transient) errors.
  #
  # Transient errors represent temporary failures that may succeed if retried,
  # such as network timeouts, rate limiting, or temporary server issues.
  # The retry middleware automatically retries operations that raise TransientError.
  #
  # @example Catching all transient errors
  #   begin
  #     client.query.ticker("AAPL").search
  #   rescue SecApi::TransientError => e
  #     # Auto-retry already attempted (5 times by default)
  #     logger.error("Operation failed after retries: #{e.message}")
  #   end
  #
  # @see PermanentError for non-retryable errors
  class TransientError < Error
  end
end
