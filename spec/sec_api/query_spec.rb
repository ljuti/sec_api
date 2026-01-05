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

  describe "#date_range (Story 2.2, AC: #3, #4, #5)" do
    context "with ISO 8601 strings (AC: #3)" do
      it "builds correct Lucene range query" do
        stubs.post("/") do |env|
          body = JSON.parse(env.body)
          expect(body["query"]).to eq("filedAt:[2020-01-01 TO 2023-12-31]")
          [200, json_headers, empty_response]
        end

        client.query.date_range(from: "2020-01-01", to: "2023-12-31").search
      end
    end

    context "with Date objects (AC: #4)" do
      it "coerces Date objects to ISO 8601 strings" do
        stubs.post("/") do |env|
          body = JSON.parse(env.body)
          expect(body["query"]).to eq("filedAt:[2020-01-01 TO 2023-12-31]")
          [200, json_headers, empty_response]
        end

        client.query.date_range(from: Date.new(2020, 1, 1), to: Date.new(2023, 12, 31)).search
      end
    end

    context "with Time objects (AC: #4)" do
      it "coerces Time objects to ISO 8601 strings" do
        stubs.post("/") do |env|
          body = JSON.parse(env.body)
          expect(body["query"]).to match(/filedAt:\[\d{4}-\d{2}-\d{2} TO \d{4}-\d{2}-\d{2}\]/)
          [200, json_headers, empty_response]
        end

        client.query.date_range(from: Time.new(2020, 1, 1), to: Time.new(2023, 12, 31)).search
      end
    end

    context "with DateTime objects" do
      it "coerces DateTime objects to ISO 8601 strings" do
        stubs.post("/") do |env|
          body = JSON.parse(env.body)
          expect(body["query"]).to eq("filedAt:[2020-01-01 TO 2023-12-31]")
          [200, json_headers, empty_response]
        end

        client.query.date_range(from: DateTime.new(2020, 1, 1), to: DateTime.new(2023, 12, 31)).search
      end
    end

    context "combined filters (AC: #5)" do
      it "combines ticker, form_type, and date_range with AND" do
        stubs.post("/") do |env|
          body = JSON.parse(env.body)
          expect(body["query"]).to eq('ticker:NEM AND formType:"10-K" AND filedAt:[2023-01-01 TO 2024-01-01]')
          [200, json_headers, empty_response]
        end

        client.query
          .ticker("NEM")
          .form_type("10-K")
          .date_range(from: Date.new(2023, 1, 1), to: Date.new(2024, 1, 1))
          .search
      end
    end

    it "returns self for method chaining" do
      query = client.query
      result = query.date_range(from: "2020-01-01", to: "2023-12-31")
      expect(result).to be(query)
      expect(result.object_id).to eq(query.object_id)
    end

    context "input validation" do
      it "raises ArgumentError when from: is nil" do
        expect {
          client.query.date_range(from: nil, to: "2023-12-31")
        }.to raise_error(ArgumentError, "from: is required")
      end

      it "raises ArgumentError when to: is nil" do
        expect {
          client.query.date_range(from: "2020-01-01", to: nil)
        }.to raise_error(ArgumentError, "to: is required")
      end

      it "raises ArgumentError for unsupported types" do
        expect {
          client.query.date_range(from: 12345, to: "2023-12-31")
        }.to raise_error(ArgumentError, /Expected Date, Time, DateTime, or ISO 8601 string/)
      end

      it "raises ArgumentError for invalid date string format" do
        expect {
          client.query.date_range(from: "not-a-date", to: "2023-12-31")
        }.to raise_error(ArgumentError, /Date string must be in ISO 8601 format/)
      end

      it "raises ArgumentError for date string with wrong separator" do
        expect {
          client.query.date_range(from: "2020/01/01", to: "2023-12-31")
        }.to raise_error(ArgumentError, /Date string must be in ISO 8601 format/)
      end

      it "raises ArgumentError for date string with time component" do
        expect {
          client.query.date_range(from: "2020-01-01T00:00:00", to: "2023-12-31")
        }.to raise_error(ArgumentError, /Date string must be in ISO 8601 format/)
      end
    end
  end

  describe "#form_type (Story 2.2, AC: #1, #2)" do
    context "with single form type (AC: #1)" do
      it "builds correct Lucene query with quoted form type" do
        stubs.post("/") do |env|
          body = JSON.parse(env.body)
          expect(body["query"]).to eq('formType:"10-K"')
          [200, json_headers, empty_response]
        end

        client.query.form_type("10-K").search
      end

      it "preserves case sensitivity (form types are case-sensitive)" do
        stubs.post("/") do |env|
          body = JSON.parse(env.body)
          expect(body["query"]).to eq('formType:"10-k"')
          [200, json_headers, empty_response]
        end

        client.query.form_type("10-k").search
      end
    end

    context "with multiple form types (AC: #2)" do
      it "builds Lucene query with formType:(\"10-K\" OR \"10-Q\") format" do
        stubs.post("/") do |env|
          body = JSON.parse(env.body)
          expect(body["query"]).to eq('formType:("10-K" OR "10-Q")')
          [200, json_headers, empty_response]
        end

        client.query.form_type("10-K", "10-Q").search
      end

      it "handles three or more form types" do
        stubs.post("/") do |env|
          body = JSON.parse(env.body)
          expect(body["query"]).to eq('formType:("10-K" OR "10-Q" OR "8-K")')
          [200, json_headers, empty_response]
        end

        client.query.form_type("10-K", "10-Q", "8-K").search
      end

      it "handles form types passed as array" do
        stubs.post("/") do |env|
          body = JSON.parse(env.body)
          expect(body["query"]).to eq('formType:("10-K" OR "10-Q")')
          [200, json_headers, empty_response]
        end

        client.query.form_type(["10-K", "10-Q"]).search
      end
    end

    it "returns self for method chaining" do
      query = client.query
      result = query.form_type("10-K")
      expect(result).to be(query)
      expect(result.object_id).to eq(query.object_id)
    end

    it "combines with ticker filter using AND" do
      stubs.post("/") do |env|
        body = JSON.parse(env.body)
        expect(body["query"]).to eq('ticker:AAPL AND formType:"10-K"')
        [200, json_headers, empty_response]
      end

      client.query.ticker("AAPL").form_type("10-K").search
    end

    context "input validation" do
      it "raises ArgumentError when no form types provided" do
        expect { client.query.form_type }.to raise_error(ArgumentError, "At least one form type is required")
      end

      it "raises ArgumentError for empty array" do
        expect { client.query.form_type([]) }.to raise_error(ArgumentError, "At least one form type is required")
      end
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

  describe "#search_text (Story 2.4, AC: #1, #3)" do
    context "basic full-text search (AC: #1)" do
      it "adds quoted search terms to Lucene query" do
        stubs.post("/") do |env|
          body = JSON.parse(env.body)
          expect(body["query"]).to eq('"merger acquisition"')
          [200, json_headers, empty_response]
        end

        client.query.search_text("merger acquisition").search
      end

      it "strips whitespace from search terms" do
        stubs.post("/") do |env|
          body = JSON.parse(env.body)
          expect(body["query"]).to eq('"merger acquisition"')
          [200, json_headers, empty_response]
        end

        client.query.search_text("  merger acquisition  ").search
      end
    end

    context "combined with other filters (AC: #3)" do
      it "combines with ticker filter" do
        stubs.post("/") do |env|
          body = JSON.parse(env.body)
          expect(body["query"]).to eq('ticker:AAPL AND "acquisition"')
          [200, json_headers, empty_response]
        end

        client.query.ticker("AAPL").search_text("acquisition").search
      end

      it "combines with ticker and form_type filters" do
        stubs.post("/") do |env|
          body = JSON.parse(env.body)
          expect(body["query"]).to eq('ticker:AAPL AND formType:"8-K" AND "acquisition"')
          [200, json_headers, empty_response]
        end

        client.query.ticker("AAPL").form_type("8-K").search_text("acquisition").search
      end
    end

    it "returns self for method chaining" do
      query = client.query
      result = query.search_text("acquisition")
      expect(result).to be(query)
      expect(result.object_id).to eq(query.object_id)
    end

    context "input validation" do
      it "raises ArgumentError for nil keywords" do
        expect { client.query.search_text(nil) }.to raise_error(ArgumentError, "Search keywords are required")
      end

      it "raises ArgumentError for empty string" do
        expect { client.query.search_text("") }.to raise_error(ArgumentError, "Search keywords are required")
      end

      it "raises ArgumentError for whitespace-only string" do
        expect { client.query.search_text("   ") }.to raise_error(ArgumentError, "Search keywords are required")
      end
    end

    context "Lucene special character escaping (code review fix)" do
      it "escapes double quotes in search terms" do
        stubs.post("/") do |env|
          body = JSON.parse(env.body)
          # Input: merger "hostile" takeover -> Lucene: "merger \"hostile\" takeover"
          expect(body["query"]).to eq('"merger \"hostile\" takeover"')
          [200, json_headers, empty_response]
        end

        client.query.search_text('merger "hostile" takeover').search
      end

      it "escapes backslashes in search terms" do
        stubs.post("/") do |env|
          body = JSON.parse(env.body)
          # Input: path\to\file -> Lucene: "path\\to\\file"
          expect(body["query"]).to eq('"path\\\\to\\\\file"')
          [200, json_headers, empty_response]
        end

        client.query.search_text('path\to\file').search
      end

      it "escapes both quotes and backslashes together" do
        stubs.post("/") do |env|
          body = JSON.parse(env.body)
          # Input: say "hello\world" -> Lucene: "say \"hello\\world\""
          expect(body["query"]).to eq('"say \"hello\\\\world\""')
          [200, json_headers, empty_response]
        end

        client.query.search_text('say "hello\world"').search
      end
    end

    context "multiple search_text calls" do
      it "combines multiple search terms with AND" do
        stubs.post("/") do |env|
          body = JSON.parse(env.body)
          expect(body["query"]).to eq('"merger" AND "acquisition"')
          [200, json_headers, empty_response]
        end

        client.query.search_text("merger").search_text("acquisition").search
      end
    end
  end

  describe "#limit (Story 2.4, AC: #2, #4)" do
    context "sets size parameter (AC: #2)" do
      it "sets size parameter in request payload" do
        stubs.post("/") do |env|
          body = JSON.parse(env.body)
          expect(body["size"]).to eq("10")
          [200, json_headers, empty_response]
        end

        client.query.ticker("AAPL").limit(10).search
      end

      it "accepts integer-like strings" do
        stubs.post("/") do |env|
          body = JSON.parse(env.body)
          expect(body["size"]).to eq("25")
          [200, json_headers, empty_response]
        end

        client.query.ticker("AAPL").limit("25").search
      end
    end

    context "default behavior (AC: #4)" do
      it "uses default size of 50 when not specified" do
        stubs.post("/") do |env|
          body = JSON.parse(env.body)
          expect(body["size"]).to eq("50")
          [200, json_headers, empty_response]
        end

        client.query.ticker("AAPL").search
      end
    end

    it "returns self for method chaining" do
      query = client.query
      result = query.limit(10)
      expect(result).to be(query)
      expect(result.object_id).to eq(query.object_id)
    end

    context "input validation" do
      it "raises ArgumentError for zero" do
        expect { client.query.limit(0) }.to raise_error(ArgumentError, "Limit must be a positive integer")
      end

      it "raises ArgumentError for negative numbers" do
        expect { client.query.limit(-5) }.to raise_error(ArgumentError, "Limit must be a positive integer")
      end
    end
  end

  describe "combined filters (Story 2.4, AC: #3)" do
    it "combines ticker, form_type, search_text, and limit" do
      stubs.post("/") do |env|
        body = JSON.parse(env.body)
        expect(body["query"]).to eq('ticker:AAPL AND formType:"8-K" AND "acquisition"')
        expect(body["size"]).to eq("20")
        [200, json_headers, empty_response]
      end

      client.query
        .ticker("AAPL")
        .form_type("8-K")
        .search_text("acquisition")
        .limit(20)
        .search
    end
  end

  describe "pagination support (Story 2.5)" do
    let(:filing_template) do
      {
        id: "1",
        accessionNo: "0001193125-24-001234",
        ticker: "AAPL",
        cik: "0000320193",
        formType: "10-K",
        filedAt: "2024-01-15",
        companyName: "Apple Inc",
        companyNameLong: "Apple Inc.",
        periodOfReport: "2023-12-31",
        linkToTxt: "https://example.com",
        linkToHtml: "https://example.com",
        linkToXbrl: "https://example.com",
        linkToFilingDetails: "https://example.com",
        entities: [],
        documentFormatFiles: [],
        dataFiles: []
      }
    end

    let(:first_page_response) do
      {
        filings: Array.new(50) { |i| filing_template.merge(accessionNo: "000119312524#{format("%06d", i)}") },
        total: {value: 100, relation: "eq"},
        from: "0"
      }
    end

    let(:second_page_response) do
      {
        filings: Array.new(50) { |i| filing_template.merge(accessionNo: "000119312524#{format("%06d", i + 50)}") },
        total: {value: 100, relation: "eq"},
        from: "50"
      }
    end

    it "passes client reference to Filings for pagination" do
      stubs.post("/") { [200, json_headers, first_page_response.to_json] }

      result = client.query.ticker("AAPL").search
      expect(result.has_more?).to be true
    end

    it "passes query_context to Filings for subsequent pagination requests" do
      # First page request
      stubs.post("/") do |env|
        body = JSON.parse(env.body)
        expect(body["from"]).to eq("0")
        [200, json_headers, first_page_response.to_json]
      end

      result = client.query.ticker("AAPL").limit(50).search

      # Second page request should use from=50
      stubs.post("/") do |env|
        body = JSON.parse(env.body)
        expect(body["from"]).to eq("50")
        expect(body["query"]).to eq("ticker:AAPL")
        expect(body["size"]).to eq("50")
        [200, json_headers, second_page_response.to_json]
      end

      next_page = result.fetch_next_page
      expect(next_page).to be_a(SecApi::Collections::Filings)
    end

    it "enables chained pagination through multiple pages" do
      stubs.post("/") { [200, json_headers, first_page_response.to_json] }
      result = client.query.ticker("AAPL").search

      # Iterate first page before fetching next (Task 5.9 requirement)
      first_page_tickers = result.map(&:ticker)
      expect(first_page_tickers).to all(eq("AAPL"))
      expect(result.to_a.size).to eq(50)

      stubs.post("/") { [200, json_headers, second_page_response.to_json] }
      page2 = result.fetch_next_page

      expect(page2.has_more?).to be false # 100 total, 50+50 fetched
    end
  end
end
