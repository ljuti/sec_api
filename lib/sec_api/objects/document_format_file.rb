require "dry/struct"

module SecApi
  module Objects
    class DocumentFormatFile < Dry::Struct
      transform_keys { |key| key.to_s.underscore }
      transform_keys(&:to_sym)

      attribute :sequence, Types::String
      attribute? :description, Types::String
      attribute :type, Types::String
      attribute :url, Types::String
      attribute :size, Types::Coercible::Integer

      def self.from_api(data)
        data[:url] = data.delete(:documentUrl) if data.key?(:documentUrl)

        new(data)
      end
    end
  end
end
