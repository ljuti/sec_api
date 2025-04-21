require "dry/struct"

module SecApi
  module Objects
    class FulltextResult < Dry::Struct
      transform_keys { |key| key.to_s.underscore }
      transform_keys(&:to_sym)

      attribute :cik, Types::String
      attribute :ticker, Types::String
      attribute :company_name_long, Types::String
      attribute :form_type, Types::String
      attribute :url, Types::String
      attribute :type, Types::String
      attribute :description, Types::String
      attribute :filed_on, Types::String

      def self.from_api(data)
        data[:company_name_long] = data.delete(:companyNameLong) if data.key?(:companyNameLong)
        data[:form_type] = data.delete(:formType) if data.key?(:formType)
        data[:url] = data.delete(:filingUrl) if data.key?(:filingUrl)
        data[:filed_on] = data.delete(:filedAt) if data.key?(:filedAt)

        new(data)
      end
    end
  end
end