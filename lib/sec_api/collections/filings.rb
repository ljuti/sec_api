require "sec_api/objects/filing"

module SecApi
  module Collections
    class Filings
      def initialize(data)
        @_data = data
        build_objects
        build_metadata
      end

      attr_reader :metadata, :objects

      def filings
        @objects
      end

      def build_objects
        @objects = @_data[:filings].map do |filing_data|
          Objects::Filing.from_api(filing_data)
        end
      end

      def build_metadata
        {}
      end
    end
  end
end
