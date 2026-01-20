require "dry/struct"
require "sec_api/objects/data_file"
require "sec_api/objects/document_format_file"
require "sec_api/objects/entity"

module SecApi
  module Objects
    # Represents an SEC filing with complete metadata.
    #
    # Filing objects are immutable (frozen) and thread-safe for concurrent access.
    # All date strings are automatically coerced to Ruby Date objects via Dry::Types.
    #
    # @example Accessing filing metadata
    #   filing = client.query.where(ticker: "AAPL").first
    #   filing.ticker         #=> "AAPL"
    #   filing.form_type      #=> "10-K"
    #   filing.accession_no   #=> "0000320193-24-000001"
    #   filing.filed_at       #=> #<Date: 2024-01-15>
    #   filing.filing_url     #=> "https://sec.gov/..."
    #
    # @see SecApi::Collections::Filings
    class Filing < Dry::Struct
      transform_keys { |key| key.to_s.underscore }
      transform_keys(&:to_sym)

      # @!attribute [r] id
      #   @return [String] unique filing identifier
      attribute :id, Types::String

      # @!attribute [r] cik
      #   @return [String] SEC Central Index Key (e.g., "320193")
      attribute :cik, Types::String

      # @!attribute [r] ticker
      #   @return [String] company stock ticker symbol (e.g., "AAPL")
      attribute :ticker, Types::String

      # @!attribute [r] company_name
      #   @return [String] company name (e.g., "Apple Inc")
      attribute :company_name, Types::String

      # @!attribute [r] company_name_long
      #   @return [String] full company name (e.g., "Apple Inc.")
      attribute :company_name_long, Types::String

      # @!attribute [r] form_type
      #   @return [String] SEC form type. Includes both domestic forms (10-K, 10-Q, 8-K, etc.)
      #     and international forms (20-F, 40-F, 6-K for foreign private issuers).
      #   @note Filing objects handle all form types uniformly - no special handling for
      #     international forms. The same structure applies to domestic and foreign filings.
      #   @see SecApi::Query::INTERNATIONAL_FORM_TYPES
      #   @see SecApi::Query::DOMESTIC_FORM_TYPES
      #   @example Domestic filing
      #     filing.form_type  #=> "10-K"
      #   @example Foreign private issuer annual report
      #     filing.form_type  #=> "20-F"
      #   @example Canadian issuer annual report (MJDS)
      #     filing.form_type  #=> "40-F"
      #   @example Foreign current report
      #     filing.form_type  #=> "6-K"
      attribute :form_type, Types::String

      # @!attribute [r] period_of_report
      #   @return [String] reporting period end date
      attribute :period_of_report, Types::String

      # @!attribute [r] filed_at
      #   @return [Date] filing date (automatically coerced from string via Dry::Types)
      attribute :filed_at, Types::JSON::Date

      # @!attribute [r] txt_url
      #   @return [String] URL to plain text filing
      attribute :txt_url, Types::String

      # @!attribute [r] html_url
      #   @return [String] URL to HTML filing
      attribute :html_url, Types::String

      # @!attribute [r] xbrl_url
      #   @return [String] URL to XBRL filing
      attribute :xbrl_url, Types::String

      # @!attribute [r] filing_details_url
      #   @return [String] URL to filing details page
      attribute :filing_details_url, Types::String

      # @!attribute [r] entities
      #   @return [Array<Entity>] associated entities
      attribute :entities, Types::Array.of(Entity)

      # @!attribute [r] documents
      #   @return [Array<DocumentFormatFile>] document format files
      attribute :documents, Types::Array.of(DocumentFormatFile)

      # @!attribute [r] data_files
      #   @return [Array<DataFile>] associated data files
      attribute :data_files, Types::Array.of(DataFile)

      # @!attribute [r] accession_number
      #   @return [String] SEC accession number (e.g., "0000320193-24-000001")
      attribute :accession_number, Types::String

      # @!attribute [r] description
      #   @return [String, nil] optional filing description
      attribute? :description, Types::String.optional

      # @!attribute [r] series_and_classes_contracts_information
      #   @return [Array<Hash>, nil] series and classes/contracts info (mutual funds, ETFs)
      attribute? :series_and_classes_contracts_information, Types::Array.of(Types::Hash).optional

      # @!attribute [r] effectiveness_date
      #   @return [String, nil] effectiveness date for registration statements
      attribute? :effectiveness_date, Types::String.optional

      # Override constructor to ensure immutability
      def initialize(attributes)
        super
        freeze
      end

      # Returns the preferred filing URL (HTML if available, otherwise TXT).
      #
      # @return [String, nil] the filing URL or nil if neither available
      # @example
      #   filing.url #=> "https://sec.gov/Archives/..."
      def url
        return html_url unless html_url.nil? || html_url.empty?
        return txt_url unless txt_url.nil? || txt_url.empty?
        nil
      end

      # Alias for {#accession_number}.
      #
      # @return [String] SEC accession number
      # @example
      #   filing.accession_no #=> "0000320193-24-000001"
      def accession_no
        accession_number
      end

      # Alias for {#url}. Returns the preferred filing URL.
      #
      # @return [String, nil] the filing URL or nil if neither available
      # @example
      #   filing.filing_url #=> "https://sec.gov/Archives/..."
      def filing_url
        url
      end

      # Creates a Filing from API response data.
      #
      # Normalizes camelCase keys from the API to snake_case and recursively
      # builds nested Entity, DocumentFormatFile, and DataFile objects.
      #
      # @param data [Hash] API response hash with filing data
      # @return [Filing] Immutable filing object
      #
      # @example
      #   data = { id: "abc123", ticker: "AAPL", formType: "10-K", ... }
      #   filing = Filing.from_api(data)
      #   filing.form_type  # => "10-K"
      #
      def self.from_api(data)
        data[:company_name] = data.delete(:companyName) if data.key?(:companyName)
        data[:company_name_long] = data.delete(:companyNameLong) if data.key?(:companyNameLong)
        data[:form_type] = data.delete(:formType) if data.key?(:formType)
        data[:period_of_report] = data.delete(:periodOfReport) if data.key?(:periodOfReport)
        data[:filed_at] = data.delete(:filedAt) if data.key?(:filedAt)
        data[:txt_url] = data.delete(:linkToTxt) if data.key?(:linkToTxt)
        data[:html_url] = data.delete(:linkToHtml) if data.key?(:linkToHtml)
        data[:xbrl_url] = data.delete(:linkToXbrl) if data.key?(:linkToXbrl)
        data[:filing_details_url] = data.delete(:linkToFilingDetails) if data.key?(:linkToFilingDetails)
        data[:documents] = data.delete(:documentFormatFiles) if data.key?(:documentFormatFiles)
        data[:data_files] = data.delete(:dataFiles) if data.key?(:dataFiles)
        data[:accession_number] = data.delete(:accessionNo) if data.key?(:accessionNo)
        data[:series_and_classes_contracts_information] = data.delete(:seriesAndClassesContractsInformation) if data.key?(:seriesAndClassesContractsInformation)
        data[:effectiveness_date] = data.delete(:effectivenessDate) if data.key?(:effectivenessDate)

        entities = data[:entities].map do |entity|
          Entity.from_api(entity)
        end

        documents = data[:documents].map do |document|
          DocumentFormatFile.from_api(document)
        end

        data_files = data[:data_files].map do |data_file|
          DataFile.from_api(data_file)
        end
        data[:entities] = entities
        data[:documents] = documents
        data[:data_files] = data_files
        new(data)
      end
    end
  end
end
