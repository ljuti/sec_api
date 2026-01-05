module SecApi
  # Extractor proxy for document extraction endpoints
  #
  # All extractor methods return immutable ExtractedData objects (not raw hashes).
  # This ensures thread safety and a consistent API surface.
  #
  # @example Extract text from filing
  #   extracted = client.extractor.extract(filing_url)
  #   extracted.text              # => "Full extracted text..."
  #   extracted.sections          # => { risk_factors: "...", financials: "..." }
  #   extracted.metadata          # => { source_url: "...", form_type: "10-K" }
  class Extractor
    def initialize(client)
      @_client = client
    end

    # Extract text and sections from SEC filing
    #
    # @param filing [String, Filing] The filing URL string or Filing object
    # @param options [Hash] Additional extraction options (e.g., { sections: ["risk_factors"] })
    # @return [ExtractedData] Immutable extracted data object
    # @raise [AuthenticationError] when API key is invalid
    # @raise [NotFoundError] when filing URL is not found
    # @raise [NetworkError] when connection fails
    def extract(filing, options = {})
      url = filing.is_a?(String) ? filing : filing.url
      response = @_client.connection.post("/extractor", {url: url}.merge(options))
      ExtractedData.from_api(response.body)
    end
  end
end
