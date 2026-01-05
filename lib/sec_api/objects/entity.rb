require "dry/struct"

module SecApi
  module Objects
    class Entity < Dry::Struct
      transform_keys { |key| key.to_s.underscore }
      transform_keys(&:to_sym)

      attribute :cik, Types::String
      attribute? :name, Types::String.optional
      attribute? :irs_number, Types::String.optional
      attribute? :state_of_incorporation, Types::String.optional
      attribute? :fiscal_year_end, Types::String.optional
      attribute? :type, Types::String.optional
      attribute? :act, Types::String.optional
      attribute? :file_number, Types::String.optional
      attribute? :film_number, Types::String.optional
      attribute? :sic, Types::String.optional
      attribute? :ticker, Types::String.optional
      attribute? :exchange, Types::String.optional

      # Override constructor to ensure immutability
      def initialize(attributes)
        super
        freeze
      end

      def self.from_api(data)
        # Non-destructive normalization - create new hash instead of mutating input
        normalized = {
          cik: data[:cik] || data["cik"],
          name: data[:name] || data[:companyName] || data["name"] || data["companyName"],
          irs_number: data[:irs_number] || data[:irsNo] || data["irs_number"] || data["irsNo"],
          state_of_incorporation: data[:state_of_incorporation] || data[:stateOfIncorporation] || data["state_of_incorporation"] || data["stateOfIncorporation"],
          fiscal_year_end: data[:fiscal_year_end] || data[:fiscalYearEnd] || data["fiscal_year_end"] || data["fiscalYearEnd"],
          type: data[:type] || data["type"],
          act: data[:act] || data["act"],
          file_number: data[:file_number] || data[:fileNo] || data["file_number"] || data["fileNo"],
          film_number: data[:film_number] || data[:filmNo] || data["film_number"] || data["filmNo"],
          sic: data[:sic] || data["sic"],
          ticker: data[:ticker] || data["ticker"],
          exchange: data[:exchange] || data["exchange"]
        }

        new(normalized)
      end
    end
  end
end
