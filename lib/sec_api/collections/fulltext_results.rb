module SecApi
  module Collections
    class FulltextResults
      include Enumerable

      def initialize(data)
        @_data = data
        build_objects
        build_metadata
      end

      attr_reader :metadata, :objects

      def fulltext_results
        @objects
      end

      def each(&block)
        @objects.each(&block)
      end

      def build_objects
        @objects = @_data[:filings].map do |fulltext_result_data|
          Objects::FulltextResult.from_api(fulltext_result_data)
        end
        @objects.freeze
      end

      def build_metadata
        {}
      end
    end
  end
end
