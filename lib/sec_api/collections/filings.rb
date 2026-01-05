require "sec_api/objects/filing"

module SecApi
  module Collections
    # A collection of SEC filings with Enumerable support.
    #
    # Filings collections are returned from query operations and support
    # iteration, pagination metadata, and total count from API response.
    #
    # @example Iterating through filings
    #   filings = client.query.where(ticker: "AAPL").fetch
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
    # @see SecApi::Objects::Filing
    class Filings
      include Enumerable

      # @!attribute [r] next_cursor
      #   @return [String, nil] cursor for fetching next page of results
      # @!attribute [r] total_count
      #   @return [Hash, Integer, nil] total count from API metadata
      attr_reader :next_cursor, :total_count

      def initialize(data)
        @_data = data
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
      # @return [Boolean] true if next_cursor is present
      def has_more?
        !@next_cursor.nil?
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
        @next_cursor = @_data[:next_cursor] || @_data["next_cursor"]
        @total_count = @_data[:total] || @_data["total"]
      end

      def freeze_collection
        @objects.freeze
      end
    end
  end
end
