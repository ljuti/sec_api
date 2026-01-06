require "sec_api/objects/filing"

module SecApi
  module Collections
    # A collection of SEC filings with Enumerable support and pagination.
    #
    # Filings collections are returned from query operations and support
    # iteration, pagination metadata, total count from API response, and
    # fetching subsequent pages of results.
    #
    # @example Iterating through filings
    #   filings = client.query.ticker("AAPL").search
    #   filings.each { |f| puts f.form_type }
    #
    # @example Using Enumerable methods
    #   filings.map(&:ticker)           #=> ["AAPL", "AAPL", ...]
    #   filings.select { |f| f.form_type == "10-K" }
    #   filings.first                   #=> Filing
    #
    # @example Accessing total count from API
    #   filings.count     #=> 1250 (total results, not just current page)
    #   filings.to_a.size #=> 50 (current page size)
    #
    # @example Pagination
    #   filings = client.query.ticker("AAPL").search
    #   while filings.has_more?
    #     filings.each { |f| process(f) }
    #     filings = filings.fetch_next_page
    #   end
    #
    # @see SecApi::Objects::Filing
    class Filings
      include Enumerable

      # @!attribute [r] next_cursor
      #   @return [Integer] offset position for fetching next page of results
      # @!attribute [r] total_count
      #   @return [Hash, Integer, nil] total count from API metadata
      attr_reader :next_cursor, :total_count

      # Initialize a new Filings collection.
      #
      # @param data [Hash] API response data containing filings array
      # @param client [SecApi::Client, nil] client instance for pagination requests
      # @param query_context [Hash, nil] original query parameters for pagination
      def initialize(data, client: nil, query_context: nil)
        @_data = data
        @_client = client
        @_query_context = query_context
        build_objects
        build_metadata
        freeze_collection
      end

      # Returns the array of Filing objects.
      #
      # @return [Array<Objects::Filing>] array of filing objects
      def filings
        @objects
      end

      # Yields each Filing to the block.
      # Required for Enumerable support.
      #
      # @yield [filing] each filing in the collection
      # @yieldparam filing [Objects::Filing] a filing object
      # @return [Enumerator] if no block given
      def each(&block)
        @objects.each(&block)
      end

      # Returns total count of results from API metadata, or delegates to
      # Enumerable#count when filtering.
      #
      # When called without arguments, returns the total number of matching
      # filings across all pages (from API metadata), not just the count of
      # filings in the current page.
      #
      # When called with a block or argument, delegates to Enumerable#count
      # to count filings in the current page matching the condition.
      #
      # @overload count
      #   Returns total count from API metadata
      #   @return [Integer] total count from API, or current page size if unavailable
      #
      # @overload count(item)
      #   Counts occurrences of item in current page (delegates to Enumerable)
      #   @param item [Object] the item to count
      #   @return [Integer] count of matching items in current page
      #
      # @overload count(&block)
      #   Counts filings matching block in current page (delegates to Enumerable)
      #   @yield [filing] each filing to test
      #   @return [Integer] count of filings where block returns true
      #
      # @example Total count from API
      #   filings.count     #=> 1250 (total matching filings across all pages)
      #
      # @example Filtered count in current page
      #   filings.count { |f| f.form_type == "10-K" }  #=> 5 (in current page)
      #
      # @note When filtering, only filings in the current page are counted.
      #   For total filtered count across all pages, use auto_paginate.
      def count(*args, &block)
        if block || args.any?
          super
        else
          case @total_count
          when Hash
            @total_count[:value] || @total_count["value"] || @objects.size
          when Integer
            @total_count
          else
            @objects.size
          end
        end
      end

      # Returns true if more pages of results are available.
      #
      # More pages are available when:
      # - A client reference exists (pagination requires API access)
      # - The next_cursor is less than the total count
      #
      # @return [Boolean] true if more pages can be fetched
      def has_more?
        return false if @_client.nil?
        @next_cursor < extract_total_value
      end

      # Returns a lazy enumerator that automatically paginates through all results.
      #
      # Each iteration yields a single {Filing} object. Pages are fetched on-demand
      # as the enumerator is consumed, keeping memory usage constant regardless of
      # total result count. Only the current page is held in memory; previous pages
      # become eligible for garbage collection as iteration proceeds.
      #
      # @return [Enumerator::Lazy] lazy enumerator yielding Filing objects
      # @raise [PaginationError] when no client reference available for pagination
      #
      # @example Backfill with early termination
      #   client.query
      #     .ticker("AAPL")
      #     .date_range(from: 5.years.ago, to: Date.today)
      #     .search
      #     .auto_paginate
      #     .each { |f| process(f) }
      #
      # @example Collect all results (use cautiously with large datasets)
      #   all_filings = filings.auto_paginate.to_a
      #
      # @example With filtering (Enumerable methods work with lazy enumerator)
      #   filings.auto_paginate
      #     .select { |f| f.form_type == "10-K" }
      #     .take(100)
      #     .each { |f| process(f) }
      #
      # @note Memory Efficiency: Only the current page is held in memory. Previous
      #   pages become eligible for garbage collection as iteration proceeds.
      #
      # @note Retry Behavior: Transient errors (503, timeouts) during page fetches
      #   are automatically retried by the middleware. Permanent errors (401, 404)
      #   will be raised to the caller.
      #
      # @see Query#auto_paginate Convenience method for chained queries
      def auto_paginate
        raise PaginationError, "Cannot paginate without client reference" if @_client.nil?

        Enumerator.new do |yielder|
          current_page = self

          loop do
            # Yield each filing from current page
            current_page.each { |filing| yielder << filing }

            # Stop if no more pages
            break unless current_page.has_more?

            # Fetch next page (becomes new current, old page eligible for GC)
            next_page = current_page.fetch_next_page

            # Guard against infinite loop if API returns empty page mid-pagination
            # (defensive coding against API misbehavior)
            break if next_page.to_a.empty? && current_page.next_cursor == next_page.next_cursor

            current_page = next_page
          end
        end.lazy
      end

      # Fetch the next page of results.
      #
      # Makes an API request using the stored query context with the next
      # cursor offset. Returns a new immutable Filings collection containing
      # the next page of results.
      #
      # @return [Filings] new collection with the next page of filings
      # @raise [PaginationError] when no more pages are available
      #
      # @example Manual pagination
      #   filings = client.query.ticker("AAPL").search
      #   if filings.has_more?
      #     next_page = filings.fetch_next_page
      #     next_page.each { |f| puts f.accession_number }
      #   end
      def fetch_next_page
        raise PaginationError, "No more pages available" unless has_more?

        payload = @_query_context.merge(from: @next_cursor.to_s)
        response = @_client.connection.post("/", payload)
        Filings.new(response.body, client: @_client, query_context: @_query_context)
      end

      private

      def build_objects
        filings_data = @_data[:filings] || @_data["filings"] || []
        @objects = filings_data
          .compact # Filter out nil entries from malformed API responses
          .map { |filing_data| Objects::Filing.from_api(filing_data) }
          .uniq { |filing| filing.accession_number }
      end

      def build_metadata
        from_offset = extract_from_offset
        page_size = @objects.size
        @next_cursor = from_offset + page_size
        @total_count = @_data[:total] || @_data["total"]
      end

      def extract_from_offset
        from_str = @_data[:from] || @_data["from"] || "0"
        from_str.to_i
      end

      def extract_total_value
        case @total_count
        when Hash
          @total_count[:value] || @total_count["value"] || 0
        when Integer
          @total_count
        else
          0
        end
      end

      def freeze_collection
        @objects.freeze
      end
    end
  end
end
