# frozen_string_literal: true

require_relative "sec_api/version"
require "dry-types"

module Types
  include Dry.Types()
end

require "sec_api/objects/document_format_file"
require "sec_api/objects/data_file"
require "sec_api/objects/entity"
require "sec_api/objects/filing"
require "sec_api/objects/fulltext_result"
require "sec_api/collections/filings"
require "sec_api/collections/fulltext_results"
require "sec_api/query"
require "sec_api/extractor"
require "sec_api/mapping"
require "sec_api/config"
require "sec_api/client"

module SecApi
  class Error < StandardError; end
  # Your code goes here...
end
