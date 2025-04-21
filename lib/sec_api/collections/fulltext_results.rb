module SecApi
  module Collections
    class FulltextResults
      def initialize(data)
        @_data = data
        build_objects
        build_metadata
      end

      attr_reader :metadata, :objects

      def fulltext_results
        @objects
      end

      def build_objects
        @objects = @_data[:filings].map do |fulltext_result_data|
          Objects::FulltextResult.from_api(fulltext_result_data)
        end
      end

      def build_metadata
        {}
      end
    end
  end
end