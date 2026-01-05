require "dry/struct"
require "sec_api/objects/data_file"
require "sec_api/objects/document_format_file"
require "sec_api/objects/entity"

module SecApi
  module Objects
    class Filing < Dry::Struct
      transform_keys { |key| key.to_s.underscore }
      transform_keys(&:to_sym)

      attribute :id, Types::String
      attribute :cik, Types::String
      attribute :ticker, Types::String
      attribute :company_name, Types::String
      attribute :company_name_long, Types::String
      attribute :form_type, Types::String
      attribute :period_of_report, Types::String
      attribute :filed_at, Types::String
      attribute :txt_url, Types::String
      attribute :html_url, Types::String
      attribute :xbrl_url, Types::String
      attribute :filing_details_url, Types::String
      attribute :entities, Types::Array.of(Entity)
      attribute :documents, Types::Array.of(DocumentFormatFile)
      attribute :data_files, Types::Array.of(DataFile)
      attribute :accession_number, Types::String

      def url
        return html_url unless html_url.blank?
        return txt_url unless txt_url.blank?
        nil
      end

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
