require "dry/struct"

module SecApi
  # Value objects namespace for immutable, thread-safe data structures.
  #
  # All objects in this namespace are Dry::Struct subclasses that are frozen
  # on construction. They represent API response data in a type-safe manner.
  #
  # @see SecApi::Objects::Filing SEC filing metadata
  # @see SecApi::Objects::Entity Company/issuer entity information
  # @see SecApi::Objects::StreamFiling Real-time filing notification
  # @see SecApi::Objects::XbrlData XBRL financial data
  #
  module Objects
    # Represents a company or issuer entity from SEC EDGAR.
    #
    # Entity objects are returned from mapping API calls and contain
    # identifying information such as CIK, ticker, company name, and
    # regulatory details. All instances are immutable (frozen).
    #
    # @example Entity from ticker resolution
    #   entity = client.mapping.ticker("AAPL")
    #   entity.cik      # => "0000320193"
    #   entity.ticker   # => "AAPL"
    #   entity.name     # => "Apple Inc."
    #
    # @example Entity from CIK resolution
    #   entity = client.mapping.cik("320193")
    #   entity.ticker   # => "AAPL"
    #
    # @see SecApi::Mapping Entity resolution API
    #
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
      attribute? :cusip, Types::String.optional

      # Override constructor to ensure immutability
      def initialize(attributes)
        super
        freeze
      end

      # Creates an Entity from API response data.
      #
      # Normalizes camelCase keys from the API to snake_case and handles
      # both symbol and string keys in the input hash.
      #
      # @param data [Hash] API response hash with entity data
      # @return [Entity] Immutable entity object
      #
      # @example
      #   data = { cik: "0000320193", companyName: "Apple Inc.", ticker: "AAPL" }
      #   entity = Entity.from_api(data)
      #   entity.name  # => "Apple Inc."
      #
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
          exchange: data[:exchange] || data["exchange"],
          cusip: data[:cusip] || data["cusip"]
        }

        new(normalized)
      end
    end
  end
end
