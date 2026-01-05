require "spec_helper"

RSpec.describe SecApi::Query do
  # Clear environment variables before and after tests
  around(:each) do |example|
    original_env = ENV.to_h.select { |k, _| k.start_with?("SECAPI_") }
    ENV.delete_if { |k, _| k.start_with?("SECAPI_") }
    example.run
    ENV.update(original_env)
  end

  let(:config) { SecApi::Config.new(api_key: "test_api_key_valid") }
  let(:client) { SecApi::Client.new(config) }
  let(:stubs) { Faraday::Adapter::Test::Stubs.new }

  let(:test_connection) do
    Faraday.new do |builder|
      builder.request :json
      builder.response :json, parser_options: {symbolize_names: true}
      builder.use SecApi::Middleware::ErrorHandler
      builder.adapter :test, stubs
    end
  end

  before do
    allow(client).to receive(:connection).and_return(test_connection)
  end

  after { stubs.verify_stubbed_calls }

  describe "#initialize" do
    it "initializes with builder state variables" do
      query = client.query
      expect(query.instance_variable_get(:@query_parts)).to eq([])
      expect(query.instance_variable_get(:@from_offset)).to eq(0)
      expect(query.instance_variable_get(:@page_size)).to eq(50)
      expect(query.instance_variable_get(:@sort_config)).to eq([{"filedAt" => {"order" => "desc"}}])
    end
  end

  let(:json_headers) { {"Content-Type" => "application/json"} }
  let(:empty_response) { {filings: [], total: {value: 0}}.to_json }

  describe "#ticker (AC: #1, #3, #4)" do
    context "with single ticker" do
      it "builds correct Lucene query for single ticker" do
        stubs.post("/") do |env|
          body = JSON.parse(env.body)
          expect(body["query"]).to eq("ticker:AAPL")
          [200, json_headers, empty_response]
        end

        client.query.ticker("AAPL").search
      end

      it "uppercases the ticker symbol" do
        stubs.post("/") do |env|
          body = JSON.parse(env.body)
          expect(body["query"]).to eq("ticker:AAPL")
          [200, json_headers, empty_response]
        end

        client.query.ticker("aapl").search
      end
    end

    context "with multiple tickers (AC: #3)" do
      it "builds Lucene query with ticker:(AAPL, TSLA) format for varargs" do
        stubs.post("/") do |env|
          body = JSON.parse(env.body)
          expect(body["query"]).to eq("ticker:(AAPL, TSLA)")
          [200, json_headers, empty_response]
        end

        client.query.ticker("AAPL", "TSLA").search
      end

      it "handles multiple tickers passed as array" do
        stubs.post("/") do |env|
          body = JSON.parse(env.body)
          expect(body["query"]).to eq("ticker:(AAPL, MSFT, NVDA)")
          [200, json_headers, empty_response]
        end

        client.query.ticker("AAPL", "MSFT", "NVDA").search
      end

      it "uppercases all ticker symbols" do
        stubs.post("/") do |env|
          body = JSON.parse(env.body)
          expect(body["query"]).to eq("ticker:(AAPL, TSLA)")
          [200, json_headers, empty_response]
        end

        client.query.ticker("aapl", "tsla").search
      end
    end

    it "returns self for method chaining (AC: #4)" do
      query = client.query
      result = query.ticker("AAPL")
      expect(result).to be(query)
      expect(result.object_id).to eq(query.object_id)
    end
  end

  describe "#cik (AC: #2, #4)" do
    it "builds correct Lucene query for CIK" do
      stubs.post("/") do |env|
        body = JSON.parse(env.body)
        expect(body["query"]).to eq("cik:320193")
        [200, json_headers, empty_response]
      end

      client.query.cik("320193").search
    end

    it "strips leading zeros from CIK (CRITICAL!)" do
      stubs.post("/") do |env|
        body = JSON.parse(env.body)
        expect(body["query"]).to eq("cik:320193")
        [200, json_headers, empty_response]
      end

      client.query.cik("0000320193").search
    end

    it "handles CIK as integer" do
      stubs.post("/") do |env|
        body = JSON.parse(env.body)
        expect(body["query"]).to eq("cik:320193")
        [200, json_headers, empty_response]
      end

      client.query.cik(320193).search
    end

    it "handles CIK with all leading zeros (edge case)" do
      stubs.post("/") do |env|
        body = JSON.parse(env.body)
        # "0000000123" should become "123"
        expect(body["query"]).to eq("cik:123")
        [200, json_headers, empty_response]
      end

      client.query.cik("0000000123").search
    end

    it "returns self for method chaining (AC: #4)" do
      query = client.query
      result = query.cik("320193")
      expect(result).to be(query)
    end

    context "input validation" do
      it "raises ArgumentError for empty CIK" do
        expect { client.query.cik("") }.to raise_error(ArgumentError, "CIK cannot be empty or zero")
      end

      it "raises ArgumentError for CIK of only zeros" do
        expect { client.query.cik("0") }.to raise_error(ArgumentError, "CIK cannot be empty or zero")
        expect { client.query.cik("0000") }.to raise_error(ArgumentError, "CIK cannot be empty or zero")
      end
    end
  end

  describe "#search (AC: #5)" do
    let(:complete_filing) do
      {
        id: "abc123",
        accessionNo: "0000320193-24-000001",
        formType: "10-K",
        filedAt: "2024-01-15",
        ticker: "AAPL",
        cik: "320193",
        companyName: "Apple Inc.",
        companyNameLong: "Apple Inc.",
        periodOfReport: "2023-12-31",
        linkToTxt: "https://sec.gov/filing.txt",
        linkToHtml: "https://sec.gov/filing.html",
        linkToXbrl: "https://sec.gov/filing.xbrl",
        linkToFilingDetails: "https://sec.gov/filing-details",
        entities: [],
        documentFormatFiles: [],
        dataFiles: []
      }
    end

    let(:api_response) do
      {
        filings: [complete_filing],
        total: {value: 1, relation: "eq"}
      }
    end

    it "POSTs to root endpoint (not /query)" do
      stubs.post("/") do |env|
        expect(env.url.path).to eq("/")
        [200, json_headers, api_response.to_json]
      end

      client.query.ticker("AAPL").search
    end

    it "sends correct payload structure" do
      stubs.post("/") do |env|
        body = JSON.parse(env.body)
        expect(body).to include(
          "query" => "ticker:AAPL",
          "from" => "0",
          "size" => "50",
          "sort" => [{"filedAt" => {"order" => "desc"}}]
        )
        [200, json_headers, api_response.to_json]
      end

      client.query.ticker("AAPL").search
    end

    it "returns SecApi::Collections::Filings object" do
      stubs.post("/") do |_env|
        [200, json_headers, api_response.to_json]
      end

      result = client.query.ticker("AAPL").search
      expect(result).to be_a(SecApi::Collections::Filings)
    end

    it "parses filings into Filing objects (Dry::Struct)" do
      stubs.post("/") do |_env|
        [200, json_headers, api_response.to_json]
      end

      result = client.query.ticker("AAPL").search
      expect(result.filings).to all(be_a(SecApi::Objects::Filing))
    end

    it "joins multiple query parts with AND" do
      stubs.post("/") do |env|
        body = JSON.parse(env.body)
        expect(body["query"]).to eq("ticker:AAPL AND cik:320193")
        [200, json_headers, api_response.to_json]
      end

      client.query.ticker("AAPL").cik("320193").search
    end

    context "error propagation" do
      it "raises AuthenticationError on 401" do
        stubs.post("/") { [401, {}, "Unauthorized"] }
        expect { client.query.ticker("AAPL").search }.to raise_error(SecApi::AuthenticationError)
      end

      it "raises RateLimitError on 429" do
        stubs.post("/") { [429, {}, "Rate limited"] }
        expect { client.query.ticker("AAPL").search }.to raise_error(SecApi::RateLimitError)
      end

      it "raises ServerError on 500" do
        stubs.post("/") { [500, {}, "Internal Server Error"] }
        expect { client.query.ticker("AAPL").search }.to raise_error(SecApi::ServerError)
      end

      it "raises ValidationError on 400" do
        stubs.post("/") { [400, {}, "Bad Request"] }
        expect { client.query.ticker("AAPL").search }.to raise_error(SecApi::ValidationError)
      end
    end
  end

  describe "#to_lucene" do
    it "returns the assembled Lucene query string" do
      query = client.query.ticker("AAPL")
      expect(query.to_lucene).to eq("ticker:AAPL")
    end

    it "joins multiple parts with AND" do
      query = client.query.ticker("AAPL").cik("320193")
      expect(query.to_lucene).to eq("ticker:AAPL AND cik:320193")
    end

    it "returns empty string when no query parts" do
      query = client.query
      expect(query.to_lucene).to eq("")
    end
  end

  describe "method chaining (AC: #4)" do
    it "all builder methods return self (same object)" do
      query = client.query
      chained = query.ticker("AAPL").cik("320193")

      expect(chained.object_id).to eq(query.object_id)
    end

    it "each chained call returns the same Query instance" do
      query = client.query
      chain1 = query.ticker("AAPL")
      chain2 = chain1.cik("320193")

      expect(chain1).to be(query)
      expect(chain2).to be(query)
      expect(chain2).to be(chain1)
    end
  end

  describe "full workflow integration (AC: #1, #2, #5)" do
    let(:complete_apple_filing) do
      {
        id: "filing1",
        accessionNo: "0000320193-24-000001",
        formType: "10-K",
        filedAt: "2024-01-15",
        ticker: "AAPL",
        cik: "320193",
        companyName: "Apple Inc.",
        companyNameLong: "Apple Inc.",
        periodOfReport: "2023-12-31",
        linkToTxt: "https://sec.gov/filing.txt",
        linkToHtml: "https://sec.gov/filing.html",
        linkToXbrl: "https://sec.gov/filing.xbrl",
        linkToFilingDetails: "https://sec.gov/filing-details",
        entities: [],
        documentFormatFiles: [],
        dataFiles: []
      }
    end

    let(:apple_filing_response) do
      {
        filings: [complete_apple_filing],
        total: {value: 1}
      }
    end

    it "client.query.ticker('AAPL').search returns filings for Apple (AC: #1)" do
      stubs.post("/") do |env|
        body = JSON.parse(env.body)
        expect(body["query"]).to eq("ticker:AAPL")
        [200, json_headers, apple_filing_response.to_json]
      end

      result = client.query.ticker("AAPL").search

      expect(result).to be_a(SecApi::Collections::Filings)
      expect(result.filings.first.ticker).to eq("AAPL")
    end

    it "client.query.cik('0000320193').search returns filings for that CIK (AC: #2)" do
      stubs.post("/") do |env|
        body = JSON.parse(env.body)
        expect(body["query"]).to eq("cik:320193")
        [200, json_headers, apple_filing_response.to_json]
      end

      result = client.query.cik("0000320193").search

      expect(result).to be_a(SecApi::Collections::Filings)
      expect(result.filings.first.cik).to eq("320193")
    end

    it "client.query.ticker('AAPL', 'TSLA').search returns filings for both (AC: #3)" do
      multi_response = {
        filings: [
          {
            id: "filing1",
            accessionNo: "0000320193-24-000001",
            formType: "10-K",
            filedAt: "2024-01-15",
            ticker: "AAPL",
            cik: "320193",
            companyName: "Apple Inc.",
            companyNameLong: "Apple Inc.",
            periodOfReport: "2023-12-31",
            linkToTxt: "https://sec.gov/filing.txt",
            linkToHtml: "https://sec.gov/filing.html",
            linkToXbrl: "https://sec.gov/filing.xbrl",
            linkToFilingDetails: "https://sec.gov/filing-details",
            entities: [],
            documentFormatFiles: [],
            dataFiles: []
          },
          {
            id: "filing2",
            accessionNo: "0001318605-24-000001",
            formType: "10-K",
            filedAt: "2024-01-20",
            ticker: "TSLA",
            cik: "1318605",
            companyName: "Tesla, Inc.",
            companyNameLong: "Tesla, Inc.",
            periodOfReport: "2023-12-31",
            linkToTxt: "https://sec.gov/filing2.txt",
            linkToHtml: "https://sec.gov/filing2.html",
            linkToXbrl: "https://sec.gov/filing2.xbrl",
            linkToFilingDetails: "https://sec.gov/filing2-details",
            entities: [],
            documentFormatFiles: [],
            dataFiles: []
          }
        ],
        total: {value: 2}
      }

      stubs.post("/") do |env|
        body = JSON.parse(env.body)
        expect(body["query"]).to eq("ticker:(AAPL, TSLA)")
        [200, json_headers, multi_response.to_json]
      end

      result = client.query.ticker("AAPL", "TSLA").search

      expect(result).to be_a(SecApi::Collections::Filings)
      expect(result.filings.map(&:ticker)).to contain_exactly("AAPL", "TSLA")
    end
  end

  describe "backward compatibility" do
    it "preserves search(query, options) signature (deprecated)" do
      stubs.post("/") do |env|
        body = JSON.parse(env.body)
        expect(body["query"]).to eq("ticker:AAPL")
        [200, json_headers, empty_response]
      end

      # Old-style direct query should still work
      result = client.query.search("ticker:AAPL")
      expect(result).to be_a(SecApi::Collections::Filings)
    end

    it "allows options to be passed with raw query" do
      stubs.post("/") do |env|
        body = JSON.parse(env.body)
        expect(body["query"]).to eq("ticker:AAPL")
        expect(body["size"]).to eq("10")
        [200, json_headers, empty_response]
      end

      client.query.search("ticker:AAPL", size: "10")
    end
  end

  describe "fresh query state per chain" do
    it "each call to client.query starts with fresh state" do
      # First query
      query1 = client.query.ticker("AAPL")
      expect(query1.to_lucene).to eq("ticker:AAPL")

      # Second query should be fresh (not include AAPL)
      query2 = client.query.ticker("TSLA")
      expect(query2.to_lucene).to eq("ticker:TSLA")
    end
  end
end
