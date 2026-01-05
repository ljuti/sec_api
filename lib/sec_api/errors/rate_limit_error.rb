# frozen_string_literal: true

module SecApi
  # Raised when sec-api.io rate limit is exceeded (429 Too Many Requests).
  #
  # This is a transient error - the retry middleware will automatically
  # retry the request after waiting for the rate limit to reset.
  #
  # @example Handling rate limits
  #   begin
  #     client.query.ticker("AAPL").search
  #   rescue SecApi::RateLimitError => e
  #     # Retries exhausted - rate limit hit repeatedly
  #     logger.warn("Rate limit exceeded: #{e.message}")
  #     notify_ops_team(e)
  #   end
  class RateLimitError < TransientError
  end
end
