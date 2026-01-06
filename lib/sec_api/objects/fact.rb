# frozen_string_literal: true

require "dry-struct"

module SecApi
  # Immutable value object representing a single XBRL fact from SEC filings.
  #
  # A fact represents a single data point in financial statements, containing
  # the value along with its context (period, units, precision).
  #
  # @example Creating a Fact with all attributes
  #   fact = SecApi::Fact.new(
  #     value: "394328000000",
  #     decimals: "-6",
  #     unit_ref: "usd",
  #     period: SecApi::Period.new(start_date: "2022-09-25", end_date: "2023-09-30")
  #   )
  #   fact.to_numeric # => 394328000000.0
  #
  # @example Creating from API response
  #   fact = SecApi::Fact.from_api({
  #     "value" => "394328000000",
  #     "decimals" => "-6",
  #     "unitRef" => "usd",
  #     "period" => {"startDate" => "2022-09-25", "endDate" => "2023-09-30"}
  #   })
  #
  class Fact < Dry::Struct
    include DeepFreezable

    transform_keys(&:to_sym)

    # The raw value from the XBRL document (always a string from API)
    attribute :value, Types::String

    # Precision indicator (e.g., "-6" means millions)
    attribute? :decimals, Types::String.optional

    # Currency or unit reference (e.g., "usd", "shares")
    attribute? :unit_ref, Types::String.optional

    # Time period for this fact (duration or instant)
    attribute? :period, Period.optional

    # Optional dimensional breakdown (for segment-level data)
    attribute? :segment, Types::Hash.optional

    # Converts the string value to a Float for calculations.
    #
    # @return [Float] Numeric value (0.0 for non-numeric strings)
    #
    # @example
    #   fact = Fact.new(value: "394328000000")
    #   fact.to_numeric # => 394328000000.0
    #
    def to_numeric
      value.to_f
    end

    def initialize(attributes)
      super
      deep_freeze(segment) if segment
      freeze
    end

    # Parses API response data into a Fact object.
    #
    # @param data [Hash] API response with camelCase or snake_case keys
    # @return [Fact] Immutable Fact object
    #
    # @example
    #   Fact.from_api({
    #     "value" => "1000000",
    #     "decimals" => "-3",
    #     "unitRef" => "usd",
    #     "period" => {"instant" => "2023-09-30"}
    #   })
    #
    def self.from_api(data)
      raw_value = data[:value] || data["value"]

      if raw_value.nil?
        raise ValidationError, "XBRL fact missing required 'value' field. " \
          "Received: #{data.inspect}"
      end

      period_data = data[:period] || data["period"]
      segment_data = data[:segment] || data["segment"]

      normalized = {
        value: raw_value.to_s,
        decimals: data[:decimals] || data["decimals"],
        unit_ref: data[:unitRef] || data["unitRef"] || data[:unit_ref] || data["unit_ref"],
        period: period_data ? Period.from_api(period_data) : nil,
        segment: segment_data
      }

      new(normalized)
    end
  end
end
