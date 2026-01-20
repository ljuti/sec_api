module SecApi
  # Collection wrappers for API response arrays.
  #
  # Collections provide Enumerable-style access to groups of value objects
  # returned from API calls, with additional methods for pagination and
  # metadata access.
  #
  # @see SecApi::Collections::Filings Filing search results
  # @see SecApi::Collections::FulltextResults Full-text search results
  #
  module Collections
    # A collection of full-text search results with Enumerable support.
    #
    # FulltextResults collections are returned from full-text search operations
    # and support iteration over matching documents.
    #
    # @example Iterating through results
    #   results = client.query.fulltext("merger acquisition")
    #   results.each { |r| puts "#{r.ticker}: #{r.description}" }
    #
    # @example Using Enumerable methods
    #   results.map(&:url)
    #   results.select { |r| r.form_type == "8-K" }
    #
    # @see SecApi::Objects::FulltextResult
    # @see SecApi::Query#fulltext
    #
    class FulltextResults
      include Enumerable

      # @return [Hash] Collection metadata (currently unused, reserved for future API enhancements)
      # @return [Array<Objects::FulltextResult>] Result objects
      attr_reader :metadata, :objects

      # Initialize a new FulltextResults collection.
      #
      # @param data [Hash] API response data containing filings array
      #
      def initialize(data)
        @_data = data
        build_objects
        build_metadata
      end

      # Returns the array of FulltextResult objects.
      #
      # @return [Array<Objects::FulltextResult>] array of result objects
      #
      def fulltext_results
        @objects
      end

      # Yields each FulltextResult to the block.
      # Required for Enumerable support.
      #
      # @yield [result] each result in the collection
      # @yieldparam result [Objects::FulltextResult] a result object
      # @return [Enumerator] if no block given
      #
      def each(&block)
        @objects.each(&block)
      end

      private

      # @api private
      def build_objects
        @objects = @_data[:filings].map do |fulltext_result_data|
          Objects::FulltextResult.from_api(fulltext_result_data)
        end
        @objects.freeze
      end

      # Builds metadata from API response.
      #
      # Currently returns an empty hash as the full-text search API does not
      # return pagination or count metadata. Reserved for future API enhancements.
      #
      # @return [Hash] Empty metadata hash
      # @api private
      def build_metadata
        @metadata = {}
      end
    end
  end
end
