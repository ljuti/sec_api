module SecApi
  # Fluent query builder for SEC filing searches using Lucene query syntax.
  #
  # Provides a chainable, ActiveRecord-style interface for building and executing
  # SEC filing queries. Each method returns `self` for chaining, with `.search`
  # as the terminal method that executes the query.
  #
  # @example Basic ticker query
  #   client.query.ticker("AAPL").search
  #   #=> SecApi::Collections::Filings
  #
  # @example Multiple tickers
  #   client.query.ticker("AAPL", "TSLA").search
  #
  # @example Query by CIK (leading zeros are automatically stripped)
  #   client.query.cik("0000320193").search
  #
  # @example Combining filters
  #   client.query.ticker("AAPL").cik("320193").search
  #
  class Query
    def initialize(client)
      @_client = client
      @query_parts = []
      @from_offset = 0
      @page_size = 50
      @sort_config = [{"filedAt" => {"order" => "desc"}}]
    end

    # Filter filings by ticker symbol(s).
    #
    # @param tickers [Array<String>] One or more ticker symbols to filter by
    # @return [self] Returns self for method chaining
    #
    # @example Single ticker
    #   query.ticker("AAPL")  #=> Lucene: "ticker:AAPL"
    #
    # @example Multiple tickers
    #   query.ticker("AAPL", "TSLA")  #=> Lucene: "ticker:(AAPL, TSLA)"
    #
    def ticker(*tickers)
      tickers = tickers.flatten.map(&:to_s).map(&:upcase)

      @query_parts << if tickers.size == 1
        "ticker:#{tickers.first}"
      else
        "ticker:(#{tickers.join(", ")})"
      end

      self
    end

    # Filter filings by Central Index Key (CIK).
    #
    # @param cik_number [String, Integer] The CIK number (leading zeros are automatically stripped)
    # @return [self] Returns self for method chaining
    # @raise [ArgumentError] when CIK is empty or contains only zeros
    #
    # @example With leading zeros (automatically stripped)
    #   query.cik("0000320193")  #=> Lucene: "cik:320193"
    #
    # @example Without leading zeros
    #   query.cik("320193")  #=> Lucene: "cik:320193"
    #
    # @note The SEC API requires CIK values WITHOUT leading zeros.
    #   This method automatically normalizes the input.
    #
    def cik(cik_number)
      normalized_cik = cik_number.to_s.gsub(/^0+/, "")
      raise ArgumentError, "CIK cannot be empty or zero" if normalized_cik.empty?
      @query_parts << "cik:#{normalized_cik}"
      self
    end

    # Execute the query and return filings.
    #
    # This is the terminal method that builds the Lucene query from accumulated
    # filters and sends it to the sec-api.io API.
    #
    # @overload search
    #   Execute the fluent query built via chained methods.
    #   @return [SecApi::Collections::Filings] Collection of filing objects
    #
    # @overload search(query, options = {})
    #   Execute a raw Lucene query string (backward-compatible signature).
    #   @param query [String] Raw Lucene query string
    #   @param options [Hash] Additional request options (from, size, sort)
    #   @return [SecApi::Collections::Filings] Collection of filing objects
    #   @deprecated Use the fluent builder methods instead
    #
    # @raise [SecApi::AuthenticationError] when API key is invalid
    # @raise [SecApi::RateLimitError] when rate limit exceeded
    # @raise [SecApi::NetworkError] when connection fails
    # @raise [SecApi::ServerError] when API returns 5xx error
    #
    # @example Fluent builder (recommended)
    #   client.query.ticker("AAPL").search
    #
    # @example Raw query (deprecated)
    #   client.query.search("ticker:AAPL AND formType:\"10-K\"")
    #
    def search(query = nil, options = {})
      if query.is_a?(String)
        # Backward-compatible: raw query string passed directly
        payload = {query: query}.merge(options)
      else
        # Fluent builder: build from accumulated query parts
        lucene_query = to_lucene
        payload = {
          query: lucene_query,
          from: @from_offset.to_s,
          size: @page_size.to_s,
          sort: @sort_config
        }
      end

      response = @_client.connection.post("/", payload)
      Collections::Filings.new(response.body)
    end

    # Returns the assembled Lucene query string for debugging/logging.
    #
    # @return [String] The Lucene query string built from accumulated filters
    #
    # @example
    #   query.ticker("AAPL").cik("320193").to_lucene
    #   #=> "ticker:AAPL AND cik:320193"
    #
    def to_lucene
      @query_parts.join(" AND ")
    end

    # Execute a full-text search across SEC filings.
    #
    # @param query [String] Full-text search query
    # @param options [Hash] Additional request options
    # @return [SecApi::FulltextResults] Full-text search results
    # @raise [SecApi::AuthenticationError] when API key is invalid
    # @raise [SecApi::RateLimitError] when rate limit exceeded
    # @raise [SecApi::NetworkError] when connection fails
    # @raise [SecApi::ServerError] when API returns 5xx error
    #
    def fulltext(query, options = {})
      response = @_client.connection.post("/full-text-search", {query: query}.merge(options))
      FulltextResults.new(response.body)
    end
  end
end
