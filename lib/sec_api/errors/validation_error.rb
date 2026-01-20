# frozen_string_literal: true

module SecApi
  # Raised when request validation fails (400, 422) or XBRL data integrity issues are detected.
  #
  # Why PermanentError? The client sent invalid data - malformed query, invalid
  # parameters, bad date format. This is a programming error or bad input that
  # won't fix itself. Also raised for XBRL data that fails heuristic validation.
  #
  # This is a permanent error - indicates malformed or incomplete filing data.
  # Retrying won't help; the filing data itself has issues that require investigation.
  #
  # @example Handling validation errors
  #   begin
  #     xbrl_data = client.xbrl_to_json(accession_no: "0001234567-21-000001")
  #   rescue SecApi::ValidationError => e
  #     # Report data quality issue
  #     logger.error("XBRL validation failed: #{e.message}")
  #     report_data_quality_issue(e)
  #   end
  class ValidationError < PermanentError
  end
end
