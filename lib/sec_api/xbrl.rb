module SecApi
  class Xbrl
    def initialize(client)
      @_client = client
    end

    # Extracts XBRL financial data from an SEC filing and returns structured, immutable XbrlData object.
    #
    # @param filing [Object] Filing object with xbrl_url and accession_number attributes
    # @param options [Hash] Optional parameters to pass to the XBRL extraction API
    # @return [SecApi::XbrlData] Immutable XBRL data object with financials, metadata, and validation_results
    # @raise [SecApi::ValidationError] When XBRL data validation fails or response is malformed
    # @raise [SecApi::AuthenticationError] When API key is invalid (401/403)
    # @raise [SecApi::RateLimitError] When rate limit is exceeded (429) - automatically retried
    # @raise [SecApi::ServerError] When sec-api.io returns 5xx errors - automatically retried
    # @raise [SecApi::NetworkError] When connection fails or times out - automatically retried
    #
    # @example Extract XBRL data from a 10-K filing
    #   client = SecApi::Client.new(api_key: "your_api_key")
    #   filing = client.query.ticker("AAPL").form_type("10-K").search.first
    #   xbrl_data = client.xbrl.to_json(filing)
    #   xbrl_data.financials[:revenue]  # => 394328000000.0
    #
    def to_json(filing, options = {})
      request_params = {}
      request_params[:"xbrl-url"] = filing.xbrl_url unless filing.xbrl_url.empty?
      request_params[:"accession-no"] = filing.accession_number unless filing.accession_number.empty?
      request_params.merge!(options) unless options.empty?

      response = @_client.connection.get("/xbrl-to-json", request_params)

      # Return XbrlData object instead of raw hash
      # Error handling delegated to middleware (Story 1.2)
      begin
        XbrlData.new(response.body)
      rescue Dry::Struct::Error => e
        # Provide actionable context when XBRL data structure validation fails
        raise ValidationError,
          "XBRL data validation failed for filing #{filing.accession_number}: #{e.message}. " \
          "This may indicate incomplete or malformed filing data from sec-api.io. " \
          "Check the filing URL and verify the XBRL document is available."
      end
    end
  end
end
