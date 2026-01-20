module SecApi
  # Extractor proxy for SEC filing section extraction
  #
  # Extracts specific sections from 10-K, 10-Q, and 8-K filings.
  # Returns extracted text or HTML content directly.
  #
  # @example Extract risk factors as text
  #   text = client.extractor.extract(filing.url, item: :risk_factors)
  #
  # @example Extract MD&A as HTML
  #   html = client.extractor.extract(filing.url, item: :mda, type: "html")
  #
  # @example Extract using item code directly
  #   text = client.extractor.extract(filing.url, item: "1A")
  class Extractor
    # Maps Ruby symbols to SEC item identifiers for 10-K filings
    # @api private
    SECTION_MAP = {
      risk_factors: "1A",
      business: "1",
      mda: "7",
      financials: "8",
      legal_proceedings: "3",
      properties: "2",
      market_risk: "7A"
    }.freeze

    # Creates a new Extractor proxy instance.
    #
    # Extractor instances are obtained via {Client#extractor} and cached
    # for reuse. Direct instantiation is not recommended.
    #
    # @param client [SecApi::Client] The parent client for API access
    # @return [SecApi::Extractor] A new extractor proxy instance
    # @api private
    def initialize(client)
      @_client = client
    end

    # Extract a specific section from an SEC filing
    #
    # @param filing [String, Filing] The filing URL string or Filing object
    # @param item [String, Symbol] Section to extract (e.g., "1A", :risk_factors, :mda)
    # @param type [String] Return format: "text" (default) or "html"
    # @return [String] The extracted section content
    # @raise [AuthenticationError] when API key is invalid
    # @raise [NotFoundError] when filing URL or section is not found
    # @raise [NetworkError] when connection fails
    #
    # @example Extract risk factors as text
    #   text = client.extractor.extract(filing.url, item: "1A")
    #   text = client.extractor.extract(filing.url, item: :risk_factors)
    #
    # @example Extract MD&A as HTML
    #   html = client.extractor.extract(filing.url, item: :mda, type: "html")
    def extract(filing, item:, type: "text")
      url = filing.is_a?(String) ? filing : filing.url
      item_code = SECTION_MAP[item.to_sym] || item.to_s

      response = @_client.connection.get("/extractor", {
        url: url,
        item: item_code,
        type: type,
        token: @_client.config.api_key
      })

      response.body
    end

  end
end
