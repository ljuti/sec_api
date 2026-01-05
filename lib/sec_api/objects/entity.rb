require "dry/struct"

module SecApi
  module Objects
    class Entity < Dry::Struct
      transform_keys { |key| key.to_s.underscore }
      transform_keys(&:to_sym)

      attribute :cik, Types::String
      attribute :name, Types::String
      attribute? :irs_number, Types::String
      attribute? :state_of_incorporation, Types::String
      attribute? :fiscal_year_end, Types::String
      attribute :type, Types::String
      attribute? :act, Types::String
      attribute :file_number, Types::String
      attribute :film_number, Types::String
      attribute :sic, Types::String

      def self.from_api(data)
        data[:name] = data.delete(:companyName) if data.key?(:companyName)
        data[:irs_number] = data.delete(:irsNo) if data.key?(:irsNo)
        data[:state_of_incorporation] = data.delete(:stateOfIncorporation) if data.key?(:stateOfIncorporation)
        data[:fiscal_year_end] = data.delete(:fiscalYearEnd) if data.key?(:fiscalYearEnd)
        data[:file_number] = data.delete(:fileNo) if data.key?(:fileNo)
        data[:film_number] = data.delete(:filmNo) if data.key?(:filmNo)

        new(data)
      end
    end
  end
end
