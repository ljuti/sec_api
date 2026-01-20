require "dry/struct"

module SecApi
  module Objects
    # Represents a full-text search result from SEC EDGAR filings.
    #
    # FulltextResult objects are returned from full-text search queries and
    # contain metadata about filings that match search terms. All instances
    # are immutable (frozen).
    #
    # @example Full-text search results
    #   results = client.query.fulltext("merger acquisition")
    #   results.each do |result|
    #     puts "#{result.ticker}: #{result.description}"
    #     puts "Filed on: #{result.filed_on}"
    #     puts "URL: #{result.url}"
    #   end
    #
    # @see SecApi::Query#fulltext Full-text search method
    # @see SecApi::Collections::FulltextResults Collection wrapper
    #
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

      # Creates a FulltextResult from API response data.
      #
      # Normalizes camelCase keys from the API to snake_case format.
      #
      # @param data [Hash] API response hash with result data
      # @return [FulltextResult] Immutable result object
      #
      # @example Create from API response
      #   data = {
      #     cik: "0000320193",
      #     ticker: "AAPL",
      #     companyNameLong: "Apple Inc.",
      #     formType: "10-K",
      #     filingUrl: "https://sec.gov/...",
      #     type: "10-K",
      #     description: "Annual report",
      #     filedAt: "2024-01-15"
      #   }
      #   result = FulltextResult.from_api(data)
      #   result.company_name_long  # => "Apple Inc."
      #
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
