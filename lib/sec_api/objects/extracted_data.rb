# frozen_string_literal: true

require "dry-struct"

module SecApi
  # Represents extracted data from SEC filings
  #
  # This immutable value object wraps extraction results from the sec-api.io
  # Extractor endpoint. All attributes are optional to handle varying API
  # response structures across different form types.
  #
  # @example Creating from API response
  #   api_response = {
  #     "text" => "Full extracted text...",
  #     "sections" => { "risk_factors" => "Risk content..." },
  #     "metadata" => { "source_url" => "https://..." }
  #   }
  #   data = SecApi::ExtractedData.from_api(api_response)
  #   data.text       # => "Full extracted text..."
  #   data.sections   # => { risk_factors: "Risk content..." }
  #
  # @example Thread-safe concurrent access
  #   threads = 10.times.map do
  #     Thread.new { data.text; data.sections }
  #   end
  #   threads.each(&:join) # No race conditions
  class ExtractedData < Dry::Struct
    include DeepFreezable

    # Transform keys to allow string or symbol input
    transform_keys(&:to_sym)

    # Full extracted text (if extracting entire filing)
    # @return [String, nil]
    attribute? :text, Types::String.optional

    # Structured sections (risk_factors, financials, etc.)
    # API returns hash like { "risk_factors": "...", "financials": "..." }
    # @return [Hash{Symbol => String}, nil]
    attribute? :sections, Types::Hash.map(Types::Symbol, Types::String).optional

    # Metadata about extraction
    # Flexible hash to handle varying API response structures
    # @return [Hash, nil]
    attribute? :metadata, Types::Hash.optional

    # Explicit freeze for immutability and thread safety
    # Deep freeze all nested hashes to ensure thread safety
    # @param attributes [Hash] The attributes hash
    def initialize(attributes)
      super
      deep_freeze(sections) if sections
      deep_freeze(metadata) if metadata
      freeze
    end

    # Normalize API response (handle string vs symbol keys)
    #
    # @param data [Hash] The raw API response
    # @return [ExtractedData] The normalized extracted data object
    def self.from_api(data)
      new(
        text: data["text"] || data[:text],
        sections: normalize_sections(data["sections"] || data[:sections]),
        metadata: data["metadata"] || data[:metadata] || {}
      )
    end

    # Normalize sections hash to symbol keys
    #
    # @param sections [Hash, nil] The sections hash from API
    # @return [Hash{Symbol => String}, nil]
    private_class_method def self.normalize_sections(sections)
      return nil unless sections
      sections.transform_keys(&:to_sym)
    end
  end
end
