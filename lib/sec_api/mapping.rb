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
    def initialize(client)
      @_client = client
    end

    # Resolve ticker symbol to company entity
    #
    # @param ticker [String] The stock ticker symbol (e.g., "AAPL")
    # @return [Entity] Immutable entity object with CIK, ticker, name, etc.
    # @raise [AuthenticationError] when API key is invalid
    # @raise [NotFoundError] when ticker is not found
    # @raise [NetworkError] when connection fails
    def ticker(ticker)
      response = @_client.connection.get("/mapping/ticker/#{ticker}")
      Objects::Entity.from_api(response.body)
    end

    # Resolve CIK number to company entity
    #
    # @param cik [String] The CIK number (e.g., "0000320193")
    # @return [Entity] Immutable entity object with CIK, ticker, name, etc.
    # @raise [AuthenticationError] when API key is invalid
    # @raise [NotFoundError] when CIK is not found
    # @raise [NetworkError] when connection fails
    def cik(cik)
      response = @_client.connection.get("/mapping/cik/#{cik}")
      Objects::Entity.from_api(response.body)
    end

    # Resolve CUSIP identifier to company entity
    #
    # @param cusip [String] The CUSIP identifier (e.g., "037833100")
    # @return [Entity] Immutable entity object with CIK, ticker, name, etc.
    # @raise [AuthenticationError] when API key is invalid
    # @raise [NotFoundError] when CUSIP is not found
    # @raise [NetworkError] when connection fails
    def cusip(cusip)
      response = @_client.connection.get("/mapping/cusip/#{cusip}")
      Objects::Entity.from_api(response.body)
    end

    # Resolve company name to entity
    #
    # @param name [String] The company name or partial name (e.g., "Apple")
    # @return [Entity] Immutable entity object with CIK, ticker, name, etc.
    # @raise [AuthenticationError] when API key is invalid
    # @raise [NotFoundError] when name is not found
    # @raise [NetworkError] when connection fails
    def name(name)
      response = @_client.connection.get("/mapping/name/#{name}")
      Objects::Entity.from_api(response.body)
    end
  end
end
