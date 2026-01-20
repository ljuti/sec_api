# frozen_string_literal: true

module SecApi
  # Raised when a requested resource is not found (404 Not Found).
  #
  # Why PermanentError? The resource genuinely doesn't exist - invalid ticker,
  # nonexistent CIK, or filing not in database. Retrying won't create it.
  # User needs to fix their query parameters or check that the resource exists.
  #
  # This is a permanent error - the requested ticker, CIK, or filing does not exist.
  # Retrying won't help; the query parameters need to be corrected.
  #
  # @example Handling not found errors
  #   begin
  #     client.query.ticker("INVALID").search
  #   rescue SecApi::NotFoundError => e
  #     # Correct the ticker symbol or filing identifier
  #     logger.warn("Resource not found: #{e.message}")
  #     prompt_user_for_valid_ticker
  #   end
  class NotFoundError < PermanentError
  end
end
