require "dry/struct"
require "sec_api/objects/document_format_file"

module SecApi
  module Objects
    # Represents a data file (XBRL, XML, etc.) within an SEC filing.
    #
    # DataFile objects inherit from {DocumentFormatFile} and represent
    # structured data files such as XBRL instance documents, XML schemas,
    # and other machine-readable attachments. All instances are immutable.
    #
    # DataFile inherits all attributes from {DocumentFormatFile}:
    # - `sequence` - File sequence number
    # - `description` - File description (optional)
    # - `type` - MIME type or file type
    # - `url` - Direct URL to download the file
    # - `size` - File size in bytes
    #
    # @example Accessing data files from a filing
    #   filing = client.query.ticker("AAPL").form_type("10-K").search.first
    #   filing.data_files.each do |file|
    #     puts "#{file.description}: #{file.url}"
    #   end
    #
    # @example Finding XBRL instance documents
    #   xbrl_files = filing.data_files.select { |f| f.type.include?("xml") }
    #
    # @see SecApi::Objects::Filing#data_files
    # @see SecApi::Objects::DocumentFormatFile Parent class with all attributes
    #
    class DataFile < DocumentFormatFile
    end
  end
end
