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
  #
  # @example Extract specific sections
  #   extracted = client.extractor.extract(filing_url, sections: [:risk_factors, :mda])
  #   extracted.risk_factors      # => "Risk factor content..."
  #   extracted.mda               # => "MD&A content..."
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

    def initialize(client)
      @_client = client
    end

    # Extract text and sections from SEC filing
    #
    # @param filing [String, Filing] The filing URL string or Filing object
    # @param sections [Array<Symbol>, nil] Specific sections to extract (e.g., [:risk_factors, :mda])
    #   When nil or omitted, extracts the full filing text.
    #   Supported sections: :risk_factors, :business, :mda, :financials, :legal_proceedings, :properties, :market_risk
    # @param options [Hash] Additional extraction options passed to the API
    # @return [ExtractedData] Immutable extracted data object
    # @raise [AuthenticationError] when API key is invalid
    # @raise [NotFoundError] when filing URL is not found
    # @raise [NetworkError] when connection fails
    # @note When extracting multiple sections, one API call is made per section.
    #   This may impact latency and API usage costs for large section lists.
    #
    # @example Extract full filing
    #   extracted = client.extractor.extract(filing_url)
    #   extracted.text  # => "Full filing text..."
    #
    # @example Extract specific section (dynamic accessor)
    #   extracted = client.extractor.extract(filing_url, sections: [:risk_factors])
    #   extracted.risk_factors  # => "Risk factors content..."
    #
    # @example Extract multiple sections (dynamic accessors)
    #   extracted = client.extractor.extract(filing_url, sections: [:risk_factors, :mda])
    #   extracted.risk_factors  # => "Risk factors..."
    #   extracted.mda           # => "MD&A analysis..."
    def extract(filing, sections: nil, **options)
      url = filing.is_a?(String) ? filing : filing.url

      if sections.nil? || sections.empty?
        # Default behavior - extract full filing
        response = @_client.connection.post("/extractor", {url: url}.merge(options))
        ExtractedData.from_api(response.body)
      else
        # Extract specified sections
        section_contents = extract_sections(url, Array(sections), options)
        ExtractedData.from_api({sections: section_contents})
      end
    end

    private

    # Extract multiple sections by making individual API calls
    #
    # @param url [String] The filing URL
    # @param sections [Array<Symbol>] List of sections to extract
    # @param options [Hash] Additional options
    # @return [Hash{Symbol => String}] Hash of section names to content
    def extract_sections(url, sections, options)
      sections.each_with_object({}) do |section, hash|
        item_id = SECTION_MAP[section.to_sym] || section.to_s
        response = @_client.connection.post("/extractor", {
          url: url,
          item: item_id
        }.merge(options))

        # API returns sections hash or text directly
        content = extract_section_content(response.body, section)
        hash[section.to_sym] = content if content
      end
    end

    # Extract section content from API response
    #
    # @param body [Hash, String] The API response body
    # @param section [Symbol] The requested section name
    # @return [String, nil] The section content
    def extract_section_content(body, section)
      return body if body.is_a?(String)
      return nil unless body.is_a?(Hash)

      # Try sections hash first, then fall back to text
      sections = body[:sections] || body["sections"]
      if sections
        sections[section.to_sym] || sections[section.to_s]
      else
        body[:text] || body["text"]
      end
    end
  end
end
