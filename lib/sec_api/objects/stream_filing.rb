# frozen_string_literal: true

module SecApi
  module Objects
    # Immutable value object representing a real-time filing from the Stream API.
    #
    # StreamFiling contains the filing metadata delivered via WebSocket when
    # a new filing is published to the SEC EDGAR system. The structure matches
    # the sec-api.io Stream API message format.
    #
    # @example Accessing filing attributes
    #   stream.subscribe do |filing|
    #     puts "#{filing.ticker}: #{filing.form_type}"
    #     puts "Filed at: #{filing.filed_at}"
    #     puts "Details: #{filing.link_to_filing_details}"
    #   end
    #
    # @note All instances are frozen (immutable) for thread-safety.
    #
    class StreamFiling < Dry::Struct
      include DeepFreezable

      # Transform incoming keys from camelCase to snake_case
      transform_keys(&:to_sym)

      # @!attribute [r] accession_no
      #   @return [String] SEC accession number (e.g., "0001193125-24-123456")
      attribute :accession_no, Types::String

      # @!attribute [r] form_type
      #   @return [String] SEC form type (e.g., "10-K", "8-K", "10-Q")
      attribute :form_type, Types::String

      # @!attribute [r] filed_at
      #   @return [String] Filing timestamp in ISO 8601 format
      attribute :filed_at, Types::String

      # @!attribute [r] cik
      #   @return [String] SEC Central Index Key
      attribute :cik, Types::String

      # @!attribute [r] ticker
      #   @return [String, nil] Stock ticker symbol (may be nil for some filers)
      attribute? :ticker, Types::String.optional

      # @!attribute [r] company_name
      #   @return [String] Company name as registered with SEC
      attribute :company_name, Types::String

      # @!attribute [r] link_to_filing_details
      #   @return [String] URL to filing details page on sec-api.io
      attribute :link_to_filing_details, Types::String

      # @!attribute [r] link_to_txt
      #   @return [String, nil] URL to plain text version of filing
      attribute? :link_to_txt, Types::String.optional

      # @!attribute [r] link_to_html
      #   @return [String, nil] URL to HTML version of filing
      attribute? :link_to_html, Types::String.optional

      # @!attribute [r] period_of_report
      #   @return [String, nil] Reporting period date (e.g., "2024-01-15")
      attribute? :period_of_report, Types::String.optional

      # @!attribute [r] entities
      #   @return [Array<Hash>, nil] Related entities from the filing
      attribute? :entities, Types::Array.of(Types::Hash).optional

      # @!attribute [r] document_format_files
      #   @return [Array<Hash>, nil] Filing document files metadata
      attribute? :document_format_files, Types::Array.of(Types::Hash).optional

      # @!attribute [r] data_files
      #   @return [Array<Hash>, nil] XBRL and other data files
      attribute? :data_files, Types::Array.of(Types::Hash).optional

      # Override constructor to ensure deep immutability.
      #
      # @api private
      def initialize(attributes)
        super
        deep_freeze(entities) if entities
        deep_freeze(document_format_files) if document_format_files
        deep_freeze(data_files) if data_files
        freeze
      end

      # Returns the preferred filing URL (HTML if available, otherwise TXT).
      #
      # This convenience method provides a single access point for the filing
      # document URL, preferring the HTML version when available.
      #
      # @return [String, nil] the filing URL or nil if neither available
      # @example
      #   filing.url #=> "https://sec.gov/Archives/..."
      #
      def url
        return link_to_html unless link_to_html.nil? || link_to_html.empty?
        return link_to_txt unless link_to_txt.nil? || link_to_txt.empty?
        nil
      end

      # Alias for {#url}. Returns the preferred filing URL.
      #
      # @return [String, nil] the filing URL or nil if neither available
      # @see #url
      #
      def filing_url
        url
      end

      # Alias for {#accession_no}. Returns the SEC accession number.
      #
      # Provides compatibility with Filing object API naming conventions.
      #
      # @return [String] SEC accession number (e.g., "0001193125-24-123456")
      # @see #accession_no
      #
      def accession_number
        accession_no
      end

      # Alias for {#link_to_html}. Returns URL to HTML version of filing.
      #
      # @return [String, nil] URL to HTML version of filing
      # @see #link_to_html
      #
      def html_url
        link_to_html
      end

      # Alias for {#link_to_txt}. Returns URL to plain text version of filing.
      #
      # @return [String, nil] URL to plain text version of filing
      # @see #link_to_txt
      #
      def txt_url
        link_to_txt
      end
    end
  end
end
