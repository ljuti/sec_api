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
  # @example Filter by form type
  #   client.query.form_type("10-K").search
  #   client.query.form_type("10-K", "10-Q").search  # Multiple types
  #
  # @example Filter by date range
  #   client.query.date_range(from: "2020-01-01", to: "2023-12-31").search
  #   client.query.date_range(from: Date.new(2020, 1, 1), to: Date.today).search
  #
  # @example Combining multiple filters
  #   client.query
  #     .ticker("AAPL")
  #     .form_type("10-K")
  #     .date_range(from: "2020-01-01", to: "2023-12-31")
  #     .search
  #
  # @example Full-text search for keywords
  #   client.query.search_text("merger acquisition").search
  #
  # @example Limit results
  #   client.query.ticker("AAPL").limit(10).search
  #
  # @example Combined search with all filters
  #   client.query
  #     .ticker("AAPL")
  #     .form_type("8-K")
  #     .search_text("acquisition")
  #     .limit(20)
  #     .search
  #
  # @example Query international filings (Form 20-F - foreign annual reports)
  #   client.query.ticker("NMR").form_type("20-F").search
  #
  # @example Query Canadian filings (Form 40-F - Canadian annual reports under MJDS)
  #   client.query.ticker("ABX").form_type("40-F").search
  #
  # @example Query foreign current reports (Form 6-K)
  #   client.query.ticker("NMR").form_type("6-K").search
  #
  # @example Mix domestic and international forms
  #   client.query.form_type("10-K", "20-F", "40-F").search
  #
  # @note International forms (20-F, 40-F, 6-K) are supported as first-class citizens.
  #   No special handling required - they work identically to domestic forms (10-K, 10-Q, 8-K).
  #
  class Query
    # Common domestic SEC form types for reference.
    # @return [Array<String>] list of common domestic form types
    # @note This is not an exhaustive list. The API accepts any form type string.
    DOMESTIC_FORM_TYPES = %w[10-K 10-Q 8-K S-1 S-3 4 13F DEF\ 14A].freeze

    # International SEC form types for foreign private issuers.
    # @return [Array<String>] list of international form types
    # @see https://www.sec.gov/divisions/corpfin/internatl/foreign-private-issuers-overview.shtml
    INTERNATIONAL_FORM_TYPES = %w[20-F 40-F 6-K].freeze

    # Combined list of common domestic and international form types.
    # @return [Array<String>] list of all common form types
    # @note This is not an exhaustive list. The API accepts any form type string.
    ALL_FORM_TYPES = (DOMESTIC_FORM_TYPES + INTERNATIONAL_FORM_TYPES).freeze

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

    # Filter filings by form type(s).
    #
    # Supports both domestic and international SEC form types. International forms
    # (20-F, 40-F, 6-K) are treated as first-class citizens - no special handling required.
    #
    # @param types [Array<String>] One or more form types to filter by
    # @return [self] Returns self for method chaining
    #
    # @example Single form type
    #   query.form_type("10-K")  #=> Lucene: 'formType:"10-K"'
    #
    # @example Multiple form types
    #   query.form_type("10-K", "10-Q")  #=> Lucene: 'formType:("10-K" OR "10-Q")'
    #
    # @example International form types
    #   query.form_type("20-F")    # Foreign private issuer annual reports
    #   query.form_type("40-F")    # Canadian issuer annual reports (MJDS)
    #   query.form_type("6-K")     # Foreign private issuer current reports
    #
    # @example Mixed domestic and international
    #   query.form_type("10-K", "20-F", "40-F")  # All annual reports
    #   query.form_type("8-K", "6-K")            # All current reports
    #
    # @note Form types are case-sensitive. "10-K" and "10-k" are different.
    # @note International forms work identically to domestic forms - no special API handling.
    # @raise [ArgumentError] when no form types are provided
    #
    def form_type(*types)
      types = types.flatten.map(&:to_s)
      raise ArgumentError, "At least one form type is required" if types.empty?

      @query_parts << if types.size == 1
        "formType:\"#{types.first}\""
      else
        quoted_types = types.map { |t| "\"#{t}\"" }.join(" OR ")
        "formType:(#{quoted_types})"
      end

      self
    end

    # Execute full-text search across filing content.
    #
    # Adds a full-text search clause to the query. The search terms are quoted
    # to match the exact phrase. Combines with other filters using AND.
    #
    # @param keywords [String] The search terms to find in filing content
    # @return [self] Returns self for method chaining
    # @raise [ArgumentError] when keywords is nil, empty, or whitespace-only
    #
    # @example Search for a phrase
    #   query.search_text("merger acquisition")
    #   #=> Lucene: '"merger acquisition"'
    #
    # @example Combined with other filters
    #   query.ticker("AAPL").form_type("8-K").search_text("acquisition")
    #   #=> Lucene: 'ticker:AAPL AND formType:"8-K" AND "acquisition"'
    #
    def search_text(keywords)
      raise ArgumentError, "Search keywords are required" if keywords.nil? || keywords.to_s.strip.empty?

      # Escape backslashes first, then quotes for valid Lucene phrase syntax
      # In gsub replacement, \\\\ (4 backslashes) produces \\ (2 actual backslashes)
      escaped = keywords.to_s.strip.gsub("\\") { "\\\\" }.gsub('"', '\\"')
      @query_parts << "\"#{escaped}\""
      self
    end

    # Limit the number of results returned.
    #
    # Sets the maximum number of filings to return in the response. When not
    # specified, defaults to 50 results.
    #
    # @param count [Integer, String] The maximum number of results (must be positive)
    # @return [self] Returns self for method chaining
    # @raise [ArgumentError] when count is zero or negative
    #
    # @example Limit to 10 results
    #   query.ticker("AAPL").limit(10).search
    #
    # @example Default behavior (50 results)
    #   query.ticker("AAPL").search  # Returns up to 50 filings
    #
    def limit(count)
      count = count.to_i
      raise ArgumentError, "Limit must be a positive integer" if count <= 0

      @page_size = count
      self
    end

    # Filter filings by date range.
    #
    # @param from [Date, Time, DateTime, String] Start date (inclusive)
    # @param to [Date, Time, DateTime, String] End date (inclusive)
    # @return [self] Returns self for method chaining
    # @raise [ArgumentError] when from or to is nil
    # @raise [ArgumentError] when from or to is an unsupported type
    # @raise [ArgumentError] when string is not in ISO 8601 format (YYYY-MM-DD)
    #
    # @example With ISO 8601 strings
    #   query.date_range(from: "2020-01-01", to: "2023-12-31")
    #
    # @example With Date objects
    #   query.date_range(from: Date.new(2020, 1, 1), to: Date.today)
    #
    # @example With Time objects (including ActiveSupport::TimeWithZone)
    #   query.date_range(from: 1.year.ago, to: Time.now)
    #
    def date_range(from:, to:)
      raise ArgumentError, "from: is required" if from.nil?
      raise ArgumentError, "to: is required" if to.nil?

      from_date = coerce_date(from)
      to_date = coerce_date(to)

      @query_parts << "filedAt:[#{from_date} TO #{to_date}]"
      self
    end

    # Executes the query and returns a lazy enumerator for automatic pagination.
    #
    # Convenience method that chains {#search} with {Filings#auto_paginate}.
    # Useful for backfill operations where you want to process all matching
    # filings across multiple pages.
    #
    # @return [Enumerator::Lazy] lazy enumerator yielding Filing objects
    # @raise [PaginationError] when pagination state is invalid
    # @raise [AuthenticationError] when API key is invalid (from search)
    # @raise [RateLimitError] when rate limit exceeded (from search)
    # @raise [NetworkError] when connection fails (from search)
    # @raise [ServerError] when API returns 5xx error (from search)
    #
    # @example Multi-year backfill
    #   client.query
    #     .ticker("AAPL")
    #     .form_type("10-K", "10-Q")
    #     .date_range(from: 5.years.ago, to: Date.today)
    #     .auto_paginate
    #     .each { |filing| ingest(filing) }
    #
    # @see Collections::Filings#auto_paginate
    def auto_paginate
      search.auto_paginate
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
        response = @_client.connection.post("/", payload)
        Collections::Filings.new(response.body)
      else
        # Fluent builder: build from accumulated query parts
        lucene_query = to_lucene
        payload = {
          query: lucene_query,
          from: @from_offset.to_s,
          size: @page_size.to_s,
          sort: @sort_config
        }

        # Store query context for pagination (excludes 'from' which changes per page)
        query_context = {
          query: lucene_query,
          size: @page_size.to_s,
          sort: @sort_config
        }

        response = @_client.connection.post("/", payload)
        Collections::Filings.new(response.body, client: @_client, query_context: query_context)
      end
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

    private

    # Coerces various date types to ISO 8601 string format (YYYY-MM-DD).
    #
    # @param value [Date, Time, DateTime, String] The date value to coerce
    # @return [String] ISO 8601 formatted date string
    # @raise [ArgumentError] when value is an unsupported type
    # @raise [ArgumentError] when string is not in ISO 8601 format (YYYY-MM-DD)
    #
    def coerce_date(value)
      case value
      when Date
        value.strftime("%Y-%m-%d")
      when Time, DateTime
        value.to_date.strftime("%Y-%m-%d")
      when String
        unless value.match?(/\A\d{4}-\d{2}-\d{2}\z/)
          raise ArgumentError, "Date string must be in ISO 8601 format (YYYY-MM-DD), got: #{value.inspect}"
        end
        value
      else
        if defined?(ActiveSupport::TimeWithZone) && value.is_a?(ActiveSupport::TimeWithZone)
          value.to_date.strftime("%Y-%m-%d")
        else
          raise ArgumentError, "Expected Date, Time, DateTime, or ISO 8601 string, got #{value.class}"
        end
      end
    end
  end
end
