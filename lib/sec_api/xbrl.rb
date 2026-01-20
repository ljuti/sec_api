module SecApi
  # XBRL extraction proxy for converting SEC EDGAR XBRL filings to structured JSON.
  #
  # Extraction Workflow:
  # 1. Client calls to_json() with URL, accession_no, or Filing object
  # 2. Input is validated locally (URL format, accession format)
  # 3. Request sent to sec-api.io XBRL-to-JSON endpoint
  # 4. Response validated heuristically (has statements? valid structure?)
  # 5. Data wrapped in immutable XbrlData Dry::Struct object
  #
  # Validation Philosophy (Architecture ADR-5):
  # We use HEURISTIC validation (check structure, required sections) rather than
  # full XBRL schema validation. Rationale:
  # - sec-api.io handles taxonomy parsing - we trust their output structure
  # - Full schema validation would require bundling 100MB+ taxonomy files
  # - We validate what matters: required sections present, data types coercible
  # - Catch malformed responses early with actionable error messages
  #
  # Provides access to the sec-api.io XBRL-to-JSON API, which extracts financial
  # statement data from XBRL filings and returns structured, typed data objects.
  # Supports both US GAAP and IFRS taxonomies.
  #
  # @example Extract XBRL data from a filing URL
  #   client = SecApi::Client.new(api_key: "your_api_key")
  #   xbrl = client.xbrl.to_json("https://www.sec.gov/Archives/edgar/data/320193/000032019323000106/aapl-20230930.htm")
  #
  #   # Access income statement data
  #   revenue = xbrl.statements_of_income["RevenueFromContractWithCustomerExcludingAssessedTax"]
  #   revenue.first.to_numeric  # => 394328000000.0
  #
  # @example Extract using accession number
  #   xbrl = client.xbrl.to_json(accession_no: "0000320193-23-000106")
  #
  # @example Extract from Filing object
  #   filing = client.query.ticker("AAPL").form_type("10-K").search.first
  #   xbrl = client.xbrl.to_json(filing)
  #
  # @example Discover available XBRL elements
  #   xbrl.element_names  # => ["Assets", "CashAndCashEquivalents", "Revenue", ...]
  #   xbrl.taxonomy_hint  # => :us_gaap or :ifrs
  #
  # @note The gem returns element names exactly as provided by sec-api.io without
  #   normalizing between US GAAP and IFRS taxonomies. Use {XbrlData#element_names}
  #   to discover available elements in any filing.
  #
  # @see SecApi::XbrlData The immutable value object returned by {#to_json}
  # @see SecApi::Fact Individual financial facts with periods and values
  #
  class Xbrl
    # Pattern for validating SEC EDGAR URLs.
    # @return [Regexp] regex pattern matching sec.gov domains
    SEC_URL_PATTERN = %r{\Ahttps?://(?:www\.)?sec\.gov/}i

    # Pattern for dashed accession number format (10-2-6 digits).
    # @return [Regexp] regex pattern for format like "0000320193-23-000106"
    # @example
    #   "0000320193-23-000106".match?(ACCESSION_DASHED_PATTERN) # => true
    ACCESSION_DASHED_PATTERN = /\A\d{10}-\d{2}-\d{6}\z/

    # Pattern for undashed accession number format (18 consecutive digits).
    # @return [Regexp] regex pattern for format like "0000320193230001060"
    # @example
    #   "0000320193230001060".match?(ACCESSION_UNDASHED_PATTERN) # => true
    ACCESSION_UNDASHED_PATTERN = /\A\d{18}\z/

    # Creates a new XBRL extraction proxy instance.
    #
    # XBRL instances are obtained via {Client#xbrl} and cached
    # for reuse. Direct instantiation is not recommended.
    #
    # @param client [SecApi::Client] The parent client for API access
    # @return [SecApi::Xbrl] A new XBRL proxy instance
    # @api private
    def initialize(client)
      @_client = client
    end

    # Extracts XBRL financial data from an SEC filing and returns structured, immutable XbrlData object.
    #
    # @overload to_json(url)
    #   Extract XBRL data from a SEC filing URL.
    #   @param url [String] SEC EDGAR URL pointing to XBRL document
    #   @return [SecApi::XbrlData] Immutable XBRL data object
    #
    # @overload to_json(accession_no:)
    #   Extract XBRL data using an accession number.
    #   @param accession_no [String] SEC accession number (e.g., "0000320193-23-000106")
    #   @return [SecApi::XbrlData] Immutable XBRL data object
    #
    # @overload to_json(filing, options = {})
    #   Extract XBRL data from a Filing object (backward compatible).
    #   @param filing [Object] Filing object with xbrl_url and accession_number attributes
    #   @param options [Hash] Optional parameters to pass to the XBRL extraction API
    #   @return [SecApi::XbrlData] Immutable XBRL data object
    #
    # @raise [SecApi::ValidationError] When input is invalid or XBRL data validation fails
    # @raise [SecApi::NotFoundError] When filing URL is invalid or has no XBRL data
    # @raise [SecApi::AuthenticationError] When API key is invalid (401/403)
    # @raise [SecApi::RateLimitError] When rate limit is exceeded (429) - automatically retried
    # @raise [SecApi::ServerError] When sec-api.io returns 5xx errors - automatically retried
    # @raise [SecApi::NetworkError] When connection fails or times out - automatically retried
    #
    # @example Extract XBRL data using URL string
    #   client = SecApi::Client.new(api_key: "your_api_key")
    #   xbrl_data = client.xbrl.to_json("https://www.sec.gov/Archives/edgar/data/320193/000032019323000106/aapl-20230930.htm")
    #
    # @example Extract XBRL data using accession number
    #   xbrl_data = client.xbrl.to_json(accession_no: "0000320193-23-000106")
    #
    # @example Extract XBRL data from Filing object (backward compatible)
    #   filing = client.query.ticker("AAPL").form_type("10-K").search.first
    #   xbrl_data = client.xbrl.to_json(filing)
    #
    def to_json(input = nil, options = {}, **kwargs)
      request_params = build_request_params(input, kwargs)
      request_params.merge!(options) unless options.empty?

      response = @_client.connection.get("/xbrl-to-json", request_params)

      # Return XbrlData object instead of raw hash.
      # XbrlData.from_api performs heuristic validation:
      # - Checks at least one statement section exists
      # - Dry::Struct validates type coercion (string/numeric values)
      # - Fact objects validate period and value structure
      # Error handling delegated to middleware (Story 1.2)
      begin
        XbrlData.from_api(response.body)
      rescue Dry::Struct::Error, NoMethodError, TypeError => e
        # Heuristic validation failed - data structure doesn't match expected format.
        # This catches issues like missing required fields, wrong types, or malformed
        # fact arrays. Provide actionable context for debugging.
        accession = request_params[:"accession-no"] || "unknown"
        raise ValidationError,
          "XBRL data validation failed for filing #{accession}: #{e.message}. " \
          "This may indicate incomplete or malformed filing data from sec-api.io. " \
          "Check the filing URL and verify the XBRL document is available."
      end
    end

    private

    def build_request_params(input, kwargs)
      # Handle keyword-only call: to_json(accession_no: "...")
      if input.nil? && kwargs[:accession_no]
        return build_params_from_accession_no(kwargs[:accession_no])
      end

      # Handle URL string input: to_json("https://...")
      if input.is_a?(String)
        return build_params_from_url(input)
      end

      # Handle Filing object input (backward compatibility): to_json(filing)
      if input.respond_to?(:xbrl_url) && input.respond_to?(:accession_number)
        return build_params_from_filing(input)
      end

      # Handle hash input with accession_no: to_json(accession_no: "...") passed as positional
      if input.is_a?(Hash) && input[:accession_no]
        return build_params_from_accession_no(input[:accession_no])
      end

      raise ValidationError, "Invalid input: expected URL string, accession_no keyword, or Filing object"
    end

    def build_params_from_url(url)
      validate_url!(url)
      {"xbrl-url": url}
    end

    def build_params_from_accession_no(accession_no)
      normalized = normalize_accession_no(accession_no)
      validate_accession_no!(normalized)
      {"accession-no": normalized}
    end

    def build_params_from_filing(filing)
      params = {}
      params[:"xbrl-url"] = filing.xbrl_url unless filing.xbrl_url.to_s.empty?
      params[:"accession-no"] = filing.accession_number unless filing.accession_number.to_s.empty?
      params
    end

    def validate_url!(url)
      begin
        uri = URI.parse(url)
        unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
          raise NotFoundError, "Filing not found: invalid URL format. URL must be a valid HTTP/HTTPS URL."
        end
      rescue URI::InvalidURIError
        raise NotFoundError, "Filing not found: invalid URL format '#{url}'. Provide a valid SEC EDGAR URL."
      end

      unless url.match?(SEC_URL_PATTERN)
        raise NotFoundError, "Filing not found: URL must be from sec.gov domain. Received: #{url}"
      end
    end

    def validate_accession_no!(accession_no)
      unless accession_no.match?(ACCESSION_DASHED_PATTERN)
        raise ValidationError,
          "Invalid accession number format: #{accession_no}. " \
          "Expected format: XXXXXXXXXX-XX-XXXXXX (10-2-6 digits)"
      end
    end

    def normalize_accession_no(accession_no)
      # Already in dashed format
      return accession_no if accession_no.match?(ACCESSION_DASHED_PATTERN)

      # Convert undashed to dashed format: 0000320193230001060 -> 0000320193-23-000106
      if accession_no.match?(ACCESSION_UNDASHED_PATTERN)
        return "#{accession_no[0, 10]}-#{accession_no[10, 2]}-#{accession_no[12, 6]}"
      end

      # Return as-is for validation to catch
      accession_no
    end
  end
end
