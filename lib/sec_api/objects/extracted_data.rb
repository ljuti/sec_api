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
    # Deep freeze all nested hashes and strings to ensure thread safety
    # @param attributes [Hash] The attributes hash
    def initialize(attributes)
      super
      text&.freeze
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

    # Access a specific section by name using dynamic method dispatch
    #
    # Allows convenient access to sections via method calls instead of hash access.
    # Returns nil for missing sections (no NoMethodError raised for section names).
    # Methods with special suffixes (!, ?, =) still raise NoMethodError.
    #
    # @param name [Symbol] The section name to access
    # @param args [Array] Additional arguments (ignored)
    # @return [String, nil] The section content or nil if not present
    #
    # @example Access risk factors section
    #   extracted.risk_factors  # => "Risk factor text..."
    #
    # @example Access missing section
    #   extracted.nonexistent   # => nil (no error)
    def method_missing(name, *args)
      # Only handle zero-argument calls (getter-style)
      return super if args.any?

      # Don't intercept bang, predicate, or setter methods
      name_str = name.to_s
      return super if name_str.end_with?("!", "?", "=")

      # Return section content if sections exist, nil otherwise
      sections&.[](name)
    end

    # Support respond_to? for sections that exist in the hash
    #
    # Only responds true for section names that are actually present
    # in the sections hash. This allows proper Ruby introspection.
    #
    # @param name [Symbol] The method name to check
    # @param include_private [Boolean] Whether to include private methods
    # @return [Boolean] true if section exists in hash
    def respond_to_missing?(name, include_private = false)
      sections&.key?(name) || super
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
