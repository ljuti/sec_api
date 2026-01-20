require "uri"

module SecApi
  # Mapping proxy for entity resolution endpoints
  #
  # All mapping methods return immutable Entity objects (not raw hashes).
  # This ensures thread safety and a consistent API surface.
  #
  # @example Ticker to CIK resolution
  #   entity = client.mapping.ticker("AAPL")
  #   entity.cik      # => "0000320193"
  #   entity.ticker   # => "AAPL"
  #   entity.name     # => "Apple Inc."
  class Mapping
    # Creates a new Mapping proxy instance.
    #
    # Mapping instances are obtained via {Client#mapping} and cached
    # for reuse. Direct instantiation is not recommended.
    #
    # @param client [SecApi::Client] The parent client for API access
    # @return [SecApi::Mapping] A new mapping proxy instance
    # @api private
    def initialize(client)
      @_client = client
    end

    # Resolve ticker symbol to company entity
    #
    # @param ticker [String] The stock ticker symbol (e.g., "AAPL", "BRK.A")
    # @return [Entity] Immutable entity object with CIK, ticker, name, etc.
    # @raise [ValidationError] when ticker is nil or empty
    # @raise [AuthenticationError] when API key is invalid
    # @raise [NotFoundError] when ticker is not found
    # @raise [NetworkError] when connection fails
    def ticker(ticker)
      validate_identifier!(ticker, "ticker")
      response = @_client.connection.get("/mapping/ticker/#{encode_path(ticker)}")
      Objects::Entity.from_api(response.body)
    end

    # Resolve CIK number to company entity
    #
    # CIK identifiers are normalized to 10 digits with leading zeros before
    # making the API request. This allows flexible input formats:
    # - "320193" -> "0000320193"
    # - "00320193" -> "0000320193"
    # - 320193 (integer) -> "0000320193"
    #
    # @param cik [String, Integer] The CIK number (e.g., "0000320193", "320193", 320193)
    # @return [Entity] Immutable entity object with CIK, ticker, name, etc.
    # @raise [ValidationError] when CIK is nil or empty
    # @raise [AuthenticationError] when API key is invalid
    # @raise [NotFoundError] when CIK is not found
    # @raise [NetworkError] when connection fails
    #
    # @example CIK without leading zeros
    #   entity = client.mapping.cik("320193")
    #   entity.cik    # => "0000320193"
    #   entity.ticker # => "AAPL"
    def cik(cik)
      validate_identifier!(cik, "CIK")
      normalized = normalize_cik(cik)
      response = @_client.connection.get("/mapping/cik/#{encode_path(normalized)}")
      Objects::Entity.from_api(response.body)
    end

    # Resolve CUSIP identifier to company entity
    #
    # @param cusip [String] The CUSIP identifier (e.g., "037833100")
    # @return [Entity] Immutable entity object with CIK, ticker, name, etc.
    # @raise [ValidationError] when CUSIP is nil or empty
    # @raise [AuthenticationError] when API key is invalid
    # @raise [NotFoundError] when CUSIP is not found
    # @raise [NetworkError] when connection fails
    def cusip(cusip)
      validate_identifier!(cusip, "CUSIP")
      response = @_client.connection.get("/mapping/cusip/#{encode_path(cusip)}")
      Objects::Entity.from_api(response.body)
    end

    # Resolve company name to entity
    #
    # @param name [String] The company name or partial name (e.g., "Apple")
    # @return [Entity] Immutable entity object with CIK, ticker, name, etc.
    # @raise [ValidationError] when name is nil or empty
    # @raise [AuthenticationError] when API key is invalid
    # @raise [NotFoundError] when name is not found
    # @raise [NetworkError] when connection fails
    def name(name)
      validate_identifier!(name, "name")
      response = @_client.connection.get("/mapping/name/#{encode_path(name)}")
      Objects::Entity.from_api(response.body)
    end

    private

    # Validates that identifier is present and non-empty
    # @param value [String, nil] The identifier value to validate
    # @param field_name [String] Human-readable field name for error message
    # @raise [ValidationError] when value is nil or empty
    def validate_identifier!(value, field_name)
      if value.nil? || value.to_s.strip.empty?
        raise ValidationError,
          "#{field_name} is required and cannot be empty. " \
          "Provide a valid #{field_name} identifier."
      end
    end

    # URL-encodes path segment for safe HTTP requests
    # Handles special characters like dots (BRK.A) and slashes
    # @param value [String] The path segment to encode
    # @return [String] URL-encoded path segment
    def encode_path(value)
      URI.encode_www_form_component(value.to_s)
    end

    # Normalizes CIK to 10 digits with leading zeros
    # SEC CIK identifiers are always 10 digits (Central Index Key)
    # @param cik [String, Integer] The CIK value to normalize
    # @return [String] 10-digit CIK with leading zeros
    def normalize_cik(cik)
      cik.to_s.gsub(/^0+/, "").rjust(10, "0")
    end
  end
end
