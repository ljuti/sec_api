# frozen_string_literal: true

module SecApi
  # Raised when API authentication fails (401 Unauthorized).
  #
  # This is a permanent error - indicates an invalid or missing API key.
  # Retrying won't help; the API key configuration must be fixed.
  #
  # @example Handling authentication errors
  #   begin
  #     client.query.ticker("AAPL").search
  #   rescue SecApi::AuthenticationError => e
  #     # Fix API key configuration
  #     logger.error("Authentication failed: #{e.message}")
  #     notify_developer("Invalid API key configuration")
  #   end
  class AuthenticationError < PermanentError
  end
end
