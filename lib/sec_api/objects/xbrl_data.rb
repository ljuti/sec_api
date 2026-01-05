# frozen_string_literal: true

require "dry-struct"

module SecApi
  # Immutable value object representing XBRL financial data extracted from SEC filings.
  #
  # This class uses Dry::Struct for type safety and immutability, ensuring thread-safe
  # access to financial metrics. All nested hashes are deeply frozen to prevent modification.
  #
  # @example Create XbrlData with financial metrics
  #   xbrl_data = SecApi::XbrlData.new(
  #     financials: {
  #       revenue: 394328000000.0,
  #       assets: 352755000000.0,
  #       liabilities: 290020000000.0
  #     },
  #     metadata: {
  #       source_url: "https://www.sec.gov/cgi-bin/viewer?action=view&cik=320193",
  #       form_type: "10-K",
  #       ticker: "AAPL"
  #     }
  #   )
  #
  # @example Access financial metrics safely across threads
  #   revenue = xbrl_data.financials[:revenue]  # Thread-safe read
  #
  # @see https://dry-rb.org/gems/dry-struct/ Dry::Struct documentation
  #
  class XbrlData < Dry::Struct
    # Transform keys to allow string or symbol input
    transform_keys(&:to_sym)

    # Financial metrics schema with strict validation and coercion
    FinancialsSchema = Types::Hash.schema(
      revenue?: Types::Coercible::Float.optional,
      total_revenue?: Types::Coercible::Float.optional,
      assets?: Types::Coercible::Float.optional,
      total_assets?: Types::Coercible::Float.optional,
      current_assets?: Types::Coercible::Float.optional,
      liabilities?: Types::Coercible::Float.optional,
      total_liabilities?: Types::Coercible::Float.optional,
      current_liabilities?: Types::Coercible::Float.optional,
      stockholders_equity?: Types::Coercible::Float.optional,
      equity?: Types::Coercible::Float.optional,
      cash_flow?: Types::Coercible::Float.optional,
      operating_cash_flow?: Types::Coercible::Float.optional,
      period_end_date?: Types::JSON::Date.optional
    ).with_key_transform(&:to_sym)

    # Metadata schema with strict validation
    MetadataSchema = Types::Hash.schema(
      source_url?: Types::String.optional,
      retrieved_at?: Types::JSON::DateTime.optional,
      form_type?: Types::String.optional,
      cik?: Types::String.optional,
      ticker?: Types::String.optional
    ).with_key_transform(&:to_sym)

    # Validation results schema
    ValidationSchema = Types::Hash.schema(
      passed?: Types::Bool.optional,
      errors?: Types::Array.of(Types::String).optional,
      warnings?: Types::Array.of(Types::String).optional
    ).with_key_transform(&:to_sym)

    # Attributes with optional schemas
    attribute :financials?, FinancialsSchema.optional
    attribute :metadata?, MetadataSchema.optional
    attribute :validation_results?, ValidationSchema.optional

    # Explicit freeze for immutability (Story 1.4 pattern)
    # Deep freeze all nested hashes to ensure thread safety
    def initialize(attributes)
      super
      deep_freeze(financials) if financials
      deep_freeze(metadata) if metadata
      deep_freeze(validation_results) if validation_results
      freeze
    end

    private

    def deep_freeze(obj)
      case obj
      when Hash
        obj.each_value { |v| deep_freeze(v) }
        obj.freeze
      when Array
        obj.each { |v| deep_freeze(v) }
        obj.freeze
      else
        obj.freeze if obj.respond_to?(:freeze)
      end
    end
  end
end
