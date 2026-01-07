# frozen_string_literal: true

# Test Helpers for sec_api gem
#
# This module provides shared helper methods for testing HTTP interactions
# using Faraday's test adapter. These patterns were established in Epic 3
# and refined through Epic 4.
#
# ## Quick Reference
#
# ### stub_connection Pattern (Mapping specs)
#
# Use when testing proxy methods that access `client.connection`:
#
#   def stub_connection(stubs)
#     allow(client).to receive(:connection).and_return(
#       Faraday.new do |conn|
#         conn.request :json
#         conn.response :json, content_type: /\bjson$/, parser_options: {symbolize_names: true}
#         conn.use SecApi::Middleware::ErrorHandler
#         conn.adapter :test, stubs
#       end
#     )
#   end
#
# ### build_connection Pattern (XBRL specs)
#
# Use when you need the connection directly (not stubbing client):
#
#   def build_connection(stubs, with_error_handler: false)
#     Faraday.new do |conn|
#       conn.request :json
#       conn.response :json, content_type: /\bjson$/, parser_options: {symbolize_names: true}
#       conn.use SecApi::Middleware::ErrorHandler if with_error_handler
#       conn.adapter :test, stubs
#     end
#   end
#
# ## Usage Examples
#
# ### Example 1: Testing a successful API response
#
#   it "returns Entity object" do
#     stubs = Faraday::Adapter::Test::Stubs.new
#     stubs.get("/mapping/ticker/AAPL") do
#       [200, {"Content-Type" => "application/json"}, {
#         "cik" => "0000320193",
#         "ticker" => "AAPL",
#         "name" => "Apple Inc."
#       }.to_json]
#     end
#     stub_connection(stubs)
#
#     entity = mapping.ticker("AAPL")
#
#     expect(entity).to be_a(SecApi::Objects::Entity)
#     stubs.verify_stubbed_calls  # IMPORTANT: Always verify!
#   end
#
# ### Example 2: Testing error responses
#
#   it "raises NotFoundError on 404" do
#     stubs = Faraday::Adapter::Test::Stubs.new
#     stubs.get("/mapping/ticker/INVALID") do
#       [404, {"Content-Type" => "application/json"}, {error: "Not found"}.to_json]
#     end
#     stub_connection(stubs)
#
#     expect { mapping.ticker("INVALID") }.to raise_error(SecApi::NotFoundError)
#     stubs.verify_stubbed_calls
#   end
#
# ### Example 3: Testing POST requests with body validation
#
#   it "sends correct request body" do
#     stubs = Faraday::Adapter::Test::Stubs.new
#     stubs.post("/xbrl-to-json") do |env|
#       body = JSON.parse(env.body)
#       expect(body["accession-no"]).to eq("0001234567-24-000001")
#       [200, {"Content-Type" => "application/json"}, response_data.to_json]
#     end
#     stub_connection(stubs)
#
#     xbrl.to_json(accession_no: "0001234567-24-000001")
#     stubs.verify_stubbed_calls
#   end
#
# ## Critical Rules
#
# 1. **Always call `stubs.verify_stubbed_calls`** in your test or `after` block
#    to ensure all stubbed endpoints were actually called.
#
# 2. **Include ErrorHandler middleware** when testing error scenarios
#    (ValidationError, NotFoundError, etc.)
#
# 3. **Use JSON content type** in response headers for proper parsing:
#    `{"Content-Type" => "application/json"}`
#
# 4. **Response body must be JSON string** - use `.to_json` on your hash:
#    `{ticker: "AAPL"}.to_json`
#
# ## Middleware Stack Order
#
# The test connection should mirror production middleware order:
#   1. :json request encoder
#   2. :json response parser
#   3. ErrorHandler middleware (converts HTTP errors to typed exceptions)
#   4. Test adapter (simulates HTTP responses)
#
# ## Common Gotchas
#
# - **Symbolized keys**: The JSON parser uses `symbolize_names: true`, so
#   response data will have symbol keys when accessed in your code.
#
# - **CIK padding**: CIK values should be 10-digit strings with leading zeros
#   (e.g., "0000320193" not "320193")
#
# - **Period data required**: XBRL Fact objects require period data. Include
#   `period: {instant: "2023-09-30"}` or `period: {startDate: "...", endDate: "..."}`
#
# ## See Also
#
# - spec/sec_api/mapping_spec.rb - stub_connection pattern examples
# - spec/sec_api/xbrl_spec.rb - build_connection pattern examples
# - spec/sec_api/extractor_spec.rb - section extraction test examples

module TestHelpers
  module Connection
    # Builds a Faraday test connection with standard middleware stack
    #
    # @param stubs [Faraday::Adapter::Test::Stubs] The test stubs instance
    # @param with_error_handler [Boolean] Include ErrorHandler middleware (default: true)
    # @return [Faraday::Connection] Configured test connection
    #
    # @example Basic usage
    #   stubs = Faraday::Adapter::Test::Stubs.new
    #   stubs.get("/test") { [200, {}, "OK"] }
    #   conn = build_test_connection(stubs)
    #   response = conn.get("/test")
    #
    def build_test_connection(stubs, with_error_handler: true)
      Faraday.new do |conn|
        conn.request :json
        conn.response :json, content_type: /\bjson$/, parser_options: {symbolize_names: true}
        conn.use SecApi::Middleware::ErrorHandler if with_error_handler
        conn.adapter :test, stubs
      end
    end

    # Stubs the client's connection method with a test connection
    #
    # @param client [SecApi::Client] The client instance to stub
    # @param stubs [Faraday::Adapter::Test::Stubs] The test stubs instance
    # @param with_error_handler [Boolean] Include ErrorHandler middleware (default: true)
    #
    # @example Stubbing client connection
    #   stubs = Faraday::Adapter::Test::Stubs.new
    #   stubs.get("/mapping/ticker/AAPL") { [200, headers, body] }
    #   stub_client_connection(client, stubs)
    #   entity = client.mapping.ticker("AAPL")
    #
    def stub_client_connection(client, stubs, with_error_handler: true)
      allow(client).to receive(:connection).and_return(
        build_test_connection(stubs, with_error_handler: with_error_handler)
      )
    end
  end

  module ResponseFixtures
    # Standard JSON response headers
    def json_headers
      {"Content-Type" => "application/json"}
    end

    # Builds a standard Entity API response
    #
    # @param ticker [String] Stock ticker symbol
    # @param cik [String] CIK number (10-digit with leading zeros)
    # @param name [String] Company name
    # @return [Hash] Entity response hash
    #
    def entity_response(ticker:, cik:, name:, **extras)
      {
        "ticker" => ticker,
        "cik" => cik,
        "name" => name
      }.merge(extras)
    end

    # Builds a standard XBRL fact for testing
    #
    # @param value [String] The fact value
    # @param period_type [Symbol] :instant or :duration
    # @return [Hash] Fact hash suitable for XBRL responses
    #
    def xbrl_fact(value:, period_type: :instant, **extras)
      period = case period_type
      when :instant
        {instant: "2023-09-30"}
      when :duration
        {startDate: "2022-10-01", endDate: "2023-09-30"}
      end

      {
        value: value,
        decimals: "-6",
        unitRef: "usd",
        period: period
      }.merge(extras)
    end
  end
end

# Include helpers in RSpec configuration
RSpec.configure do |config|
  config.include TestHelpers::Connection
  config.include TestHelpers::ResponseFixtures
end
