require "sec_api/objects/filing"

module SecApi
  module Collections
    class Filings
      include Enumerable

      attr_reader :next_cursor, :total_count

      def initialize(data)
        @_data = data
        build_objects
        build_metadata
        freeze_collection
      end

      def filings
        @objects
      end

      # Enumerable interface
      def each(&block)
        @objects.each(&block)
      end

      # Pagination helpers
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
