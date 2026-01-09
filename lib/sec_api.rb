# frozen_string_literal: true

require_relative "sec_api/version"
require "dry-struct"
require "dry-types"

# SecApi::Types module must load before objects (no top-level Types pollution)
require "sec_api/types"
require "sec_api/deep_freezable"

require "sec_api/errors/error"
require "sec_api/errors/configuration_error"
require "sec_api/errors/transient_error"
require "sec_api/errors/permanent_error"
require "sec_api/errors/rate_limit_error"
require "sec_api/errors/server_error"
require "sec_api/errors/network_error"
require "sec_api/errors/reconnection_error"
require "sec_api/errors/authentication_error"
require "sec_api/errors/not_found_error"
require "sec_api/errors/validation_error"
require "sec_api/errors/pagination_error"
require "sec_api/rate_limit_state"
require "sec_api/rate_limit_tracker"
require "sec_api/middleware/rate_limiter"
require "sec_api/middleware/error_handler"
require "sec_api/objects/document_format_file"
require "sec_api/objects/data_file"
require "sec_api/objects/entity"
require "sec_api/objects/filing"
require "sec_api/objects/fulltext_result"
require "sec_api/objects/period"
require "sec_api/objects/fact"
require "sec_api/objects/xbrl_data"
require "sec_api/objects/extracted_data"
require "sec_api/objects/stream_filing"
require "sec_api/collections/filings"
require "sec_api/collections/fulltext_results"
require "sec_api/query"
require "sec_api/extractor"
require "sec_api/mapping"
require "sec_api/config"
require "sec_api/client"
require "sec_api/xbrl"
require "sec_api/stream"

module SecApi
  # Your code goes here...
end
