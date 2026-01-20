require "dry/struct"

module SecApi
  module Objects
    # Represents a document file within an SEC filing.
    #
    # DocumentFormatFile objects contain metadata about individual documents
    # within a filing, such as the main filing document, exhibits, and
    # attachments. All instances are immutable (frozen).
    #
    # @example Accessing document files from a filing
    #   filing = client.query.ticker("AAPL").form_type("10-K").search.first
    #   filing.documents.each do |doc|
    #     puts "#{doc.sequence}: #{doc.description} (#{doc.type})"
    #     puts "URL: #{doc.url}, Size: #{doc.size} bytes"
    #   end
    #
    # @see SecApi::Objects::Filing#documents
    # @see SecApi::Objects::DataFile
    #
    class DocumentFormatFile < Dry::Struct
      transform_keys { |key| key.to_s.underscore }
      transform_keys(&:to_sym)

      attribute :sequence, Types::String
      attribute? :description, Types::String
      attribute :type, Types::String
      attribute :url, Types::String
      attribute? :size, Types::Coercible::Integer.optional

      # Creates a DocumentFormatFile from API response data.
      #
      # Normalizes camelCase keys from the API to snake_case format.
      #
      # @param data [Hash] API response hash with document data
      # @return [DocumentFormatFile] Immutable document file object
      #
      def self.from_api(data)
        data[:url] = data.delete(:documentUrl) if data.key?(:documentUrl)

        # API sometimes returns whitespace for size - normalize to nil
        # Check both symbol and string keys since API data may use either
        size_val = data[:size] || data["size"]
        if size_val.is_a?(String) && size_val.strip.empty?
          data[:size] = nil
          data.delete("size")
        end

        new(data)
      end
    end
  end
end
