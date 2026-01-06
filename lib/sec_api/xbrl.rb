module SecApi
  class Xbrl
    # SEC URL pattern for validation
    SEC_URL_PATTERN = %r{\Ahttps?://(?:www\.)?sec\.gov/}i

    # Accession number formats:
    # - Dashed: 0000320193-23-000106 (10-2-6 digits)
    # - Undashed: 0000320193230001060 (18 digits)
    ACCESSION_DASHED_PATTERN = /\A\d{10}-\d{2}-\d{6}\z/
    ACCESSION_UNDASHED_PATTERN = /\A\d{18}\z/

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

      # Return XbrlData object instead of raw hash
      # Error handling delegated to middleware (Story 1.2)
      begin
        XbrlData.from_api(response.body)
      rescue Dry::Struct::Error, NoMethodError, TypeError => e
        # Provide actionable context when XBRL data structure validation fails
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
