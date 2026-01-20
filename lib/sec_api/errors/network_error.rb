# frozen_string_literal: true

module SecApi
  # Raised when network connectivity issues occur (timeouts, connection failures).
  #
  # Why TransientError? Network issues are inherently temporary - a brief blip,
  # overloaded router, or momentary DNS failure. The request is valid; the network
  # path is temporarily broken. High probability of success on retry.
  #
  # Wrapped Faraday exceptions: TimeoutError, ConnectionFailed, SSLError.
  #
  # This is a transient error - the retry middleware will automatically
  # retry the request. Network errors represent temporary connectivity issues
  # that may resolve on subsequent attempts.
  #
  # @example Handling network errors
  #   begin
  #     client.query.ticker("AAPL").search
  #   rescue SecApi::NetworkError => e
  #     # Retries exhausted - persistent connectivity issue
  #     logger.error("Network error: #{e.message}")
  #     check_network_status
  #   end
  class NetworkError < TransientError
  end
end
