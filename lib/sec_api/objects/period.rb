# frozen_string_literal: true

require "dry-struct"

module SecApi
  # Immutable value object representing a time period for XBRL facts.
  #
  # Periods can be either:
  # - Duration: has start_date and end_date (for income statement items)
  # - Instant: has instant date (for balance sheet items)
  #
  # @example Duration period (income statement)
  #   period = SecApi::Period.new(
  #     start_date: Date.new(2022, 9, 25),
  #     end_date: Date.new(2023, 9, 30)
  #   )
  #   period.duration? # => true
  #
  # @example Instant period (balance sheet)
  #   period = SecApi::Period.new(instant: Date.new(2023, 9, 30))
  #   period.instant? # => true
  #
  class Period < Dry::Struct
    transform_keys(&:to_sym)

    attribute? :start_date, Types::JSON::Date.optional
    attribute? :end_date, Types::JSON::Date.optional
    attribute? :instant, Types::JSON::Date.optional

    # Returns true if this is a duration period (has start/end dates)
    #
    # @return [Boolean]
    def duration?
      !start_date.nil? && !end_date.nil?
    end

    # Returns true if this is an instant period (point-in-time)
    #
    # @return [Boolean]
    def instant?
      !instant.nil?
    end

    def initialize(attributes)
      super
      freeze
    end

    # Parses API response data into a Period object.
    #
    # @param data [Hash] API response with camelCase or snake_case keys
    # @return [Period] Immutable Period object
    #
    # @example
    #   Period.from_api({"startDate" => "2023-01-01", "endDate" => "2023-12-31"})
    #   Period.from_api({"instant" => "2023-09-30"})
    #
    def self.from_api(data)
      # Defensive nil check for direct calls (Fact.from_api validates period presence)
      return nil if data.nil?

      start_date = data[:startDate] || data["startDate"] || data[:start_date] || data["start_date"]
      end_date = data[:endDate] || data["endDate"] || data[:end_date] || data["end_date"]
      instant = data[:instant] || data["instant"]

      validate_structure!(instant, start_date, end_date, data)

      new(
        start_date: start_date,
        end_date: end_date,
        instant: instant
      )
    end

    # Validates that period has either instant OR (start_date AND end_date).
    #
    # @param instant [String, nil] Instant date value
    # @param start_date [String, nil] Start date value
    # @param end_date [String, nil] End date value
    # @param data [Hash] Original data for error message
    # @raise [ValidationError] when period structure is invalid
    #
    def self.validate_structure!(instant, start_date, end_date, data)
      has_instant = !instant.nil?
      has_duration = !start_date.nil? && !end_date.nil?

      return if has_instant || has_duration

      raise ValidationError, "XBRL period has invalid structure. " \
        "Expected 'instant' or 'startDate'/'endDate'. " \
        "Received: #{data.inspect}"
    end

    private_class_method :validate_structure!
  end
end
