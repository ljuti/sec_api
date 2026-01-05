# frozen_string_literal: true

module SecApi
  # Raised when XBRL data validation fails or data integrity issues are detected.
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
