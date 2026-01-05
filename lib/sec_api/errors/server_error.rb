# frozen_string_literal: true

module SecApi
  # Raised when sec-api.io returns a server error (5xx status code).
  #
  # This is a transient error - the retry middleware will automatically
  # retry the request. Server errors typically indicate temporary issues
  # with the sec-api.io infrastructure.
  #
  # @example Handling server errors
  #   begin
  #     client.query.ticker("AAPL").search
  #   rescue SecApi::ServerError => e
  #     # Retries exhausted - persistent server issue
  #     logger.error("Server error: #{e.message}")
  #     alert_on_call_team(e)
  #   end
  class ServerError < TransientError
  end
end
