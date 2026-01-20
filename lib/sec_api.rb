# frozen_string_literal: true

# Load Order Dependencies (Architecture ADR-1: Module Loading Strategy)
#
# This file establishes the load order for all SecApi modules. Order matters because:
#
# 1. Types FIRST: Dry::Types module must be defined before any Dry::Struct classes.
#    Without this, attribute declarations in value objects will fail with NameError.
#
# 2. Errors BEFORE Middleware: Middleware raises typed errors, so error classes
#    must be loaded first. Base classes before subclasses (Error → TransientError → RateLimitError).
#
# 3. Objects BEFORE Collections: Filings collection wraps Filing objects.
#
# 4. Helpers BEFORE dependents: DeepFreezable, CallbackHelper, etc. are mixed into
#    other classes and must be available when those classes are defined.
#
# 5. Config BEFORE Client: Client validates config during initialization.
#
# Never use require_relative in individual files - all loading happens here.
# This centralized approach prevents circular dependencies and makes the load
# order explicit and auditable.

require_relative "sec_api/version"
require "dry-struct"
require "dry-types"

# === Foundation Layer ===
# Types and utilities that everything else depends on

# SecApi::Types module must load FIRST - Dry::Struct classes reference these types
require "sec_api/types"
require "sec_api/deep_freezable"
require "sec_api/callback_helper"
require "sec_api/structured_logger"
require "sec_api/metrics_collector"
require "sec_api/filing_journey"

# === Error Hierarchy ===
# Base classes before subclasses (Error → TransientError → RateLimitError)
# Middleware references these error classes, so they must load first

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

# === State Tracking ===
require "sec_api/rate_limit_state"
require "sec_api/rate_limit_tracker"

# === Middleware Layer ===
# HTTP middleware for resilience and observability

require "sec_api/middleware/instrumentation"
require "sec_api/middleware/rate_limiter"
require "sec_api/middleware/error_handler"

# === Value Objects ===
# Immutable Dry::Struct objects for API responses

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

# === Collections ===
# Enumerable wrappers for API response arrays

require "sec_api/collections/filings"
require "sec_api/collections/fulltext_results"

# === API Proxies ===
# Domain-specific interfaces to API endpoints

require "sec_api/query"
require "sec_api/extractor"
require "sec_api/mapping"
require "sec_api/config"
require "sec_api/client"
require "sec_api/xbrl"
require "sec_api/stream"

# SecApi is a Ruby client library for the sec-api.io API.
#
# This gem provides programmatic access to 18+ million SEC EDGAR filings
# with production-grade error handling, resilience, and observability.
#
# @example Basic usage
#   client = SecApi::Client.new(api_key: "your_api_key")
#   filings = client.query.ticker("AAPL").form_type("10-K").search
#   filings.each { |f| puts "#{f.ticker}: #{f.form_type}" }
#
# @example Query with date range and full-text search
#   filings = client.query
#     .ticker("AAPL", "TSLA")
#     .form_type("10-K", "10-Q")
#     .date_range(from: "2020-01-01", to: "2023-12-31")
#     .search_text("revenue growth")
#     .search
#
# @example Entity resolution (ticker to CIK)
#   entity = client.mapping.ticker("AAPL")
#   puts "CIK: #{entity.cik}, Name: #{entity.name}"
#
# @example XBRL financial data extraction
#   filing = client.query.ticker("AAPL").form_type("10-K").search.first
#   xbrl = client.xbrl.to_json(filing)
#   revenue = xbrl.statements_of_income["RevenueFromContractWithCustomerExcludingAssessedTax"]
#
# @example Real-time filing notifications
#   client.stream.subscribe(tickers: ["AAPL"]) do |filing|
#     puts "New filing: #{filing.form_type} at #{filing.filed_at}"
#   end
#
# @see SecApi::Client Main entry point for API interactions
# @see SecApi::Query Fluent query builder for filing searches
# @see SecApi::Mapping Entity resolution endpoints
# @see SecApi::Xbrl XBRL data extraction
# @see SecApi::Stream Real-time WebSocket notifications
#
module SecApi
end
