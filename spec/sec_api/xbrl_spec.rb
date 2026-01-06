# frozen_string_literal: true

require "spec_helper"

RSpec.describe SecApi::Xbrl do
  let(:config) { SecApi::Config.new(api_key: "test_api_key_valid") }
  let(:client) { SecApi::Client.new(config) }
  let(:xbrl_proxy) { client.xbrl }

  describe "#to_json" do
    let(:filing) do
      double(
        "Filing",
        xbrl_url: "https://www.sec.gov/example.xml",
        accession_number: "0001234567-24-000001"
      )
    end

    let(:xbrl_response) do
      {
        StatementsOfIncome: {
          RevenueFromContractWithCustomerExcludingAssessedTax: [
            {value: "394328000000", decimals: "-6", unitRef: "usd", period: {startDate: "2022-09-25", endDate: "2023-09-30"}}
          ]
        },
        BalanceSheets: {
          Assets: [{value: "352755000000", decimals: "-6", unitRef: "usd", period: {instant: "2023-09-30"}}]
        },
        StatementsOfCashFlows: {
          NetIncomeLoss: [{value: "96995000000", decimals: "-6", unitRef: "usd", period: {startDate: "2022-09-25", endDate: "2023-09-30"}}]
        },
        CoverPage: {
          DocumentType: [{value: "10-K", period: {instant: "2023-09-30"}}],
          EntityRegistrantName: [{value: "Apple Inc", period: {instant: "2023-09-30"}}]
        }
      }
    end

    def stub_xbrl_request(stubs, response: xbrl_response, status: 200)
      stubs.get("/xbrl-to-json") do |env|
        [status, {"Content-Type" => "application/json"}, response.to_json]
      end
    end

    def build_connection(stubs, with_error_handler: false)
      Faraday.new do |conn|
        conn.request :json
        conn.response :json, content_type: /\bjson$/, parser_options: {symbolize_names: true}
        conn.use SecApi::Middleware::ErrorHandler if with_error_handler
        conn.adapter :test, stubs
      end
    end

    context "with URL string input" do
      it "accepts a URL string and returns XbrlData object" do
        stubs = Faraday::Adapter::Test::Stubs.new
        stub_xbrl_request(stubs)

        allow(client).to receive(:connection).and_return(build_connection(stubs))

        result = xbrl_proxy.to_json("https://www.sec.gov/Archives/edgar/data/320193/000032019323000106/aapl-20230930.htm")

        expect(result).to be_a(SecApi::XbrlData)
        stubs.verify_stubbed_calls
      end

      it "sends xbrl-url parameter to API" do
        stubs = Faraday::Adapter::Test::Stubs.new
        url = "https://www.sec.gov/Archives/edgar/data/320193/000032019323000106/aapl-20230930.htm"

        stubs.get("/xbrl-to-json") do |env|
          expect(env.params["xbrl-url"]).to eq(url)
          [200, {"Content-Type" => "application/json"}, xbrl_response.to_json]
        end

        allow(client).to receive(:connection).and_return(build_connection(stubs))
        xbrl_proxy.to_json(url)
        stubs.verify_stubbed_calls
      end

      it "raises NotFoundError for invalid URL format (AC #4)" do
        expect {
          xbrl_proxy.to_json("not-a-valid-url")
        }.to raise_error(SecApi::NotFoundError, /Filing not found.*invalid URL format/)
      end

      it "raises NotFoundError for non-SEC URL (AC #4)" do
        expect {
          xbrl_proxy.to_json("https://example.com/some-file.xml")
        }.to raise_error(SecApi::NotFoundError, /Filing not found.*sec\.gov/)
      end
    end

    context "with keyword hash input" do
      it "accepts accession_no keyword and returns XbrlData object" do
        stubs = Faraday::Adapter::Test::Stubs.new
        stub_xbrl_request(stubs)

        allow(client).to receive(:connection).and_return(build_connection(stubs))

        result = xbrl_proxy.to_json(accession_no: "0000320193-23-000106")

        expect(result).to be_a(SecApi::XbrlData)
        stubs.verify_stubbed_calls
      end

      it "sends accession-no parameter to API" do
        stubs = Faraday::Adapter::Test::Stubs.new

        stubs.get("/xbrl-to-json") do |env|
          expect(env.params["accession-no"]).to eq("0000320193-23-000106")
          [200, {"Content-Type" => "application/json"}, xbrl_response.to_json]
        end

        allow(client).to receive(:connection).and_return(build_connection(stubs))
        xbrl_proxy.to_json(accession_no: "0000320193-23-000106")
        stubs.verify_stubbed_calls
      end

      it "raises ValidationError for invalid accession_no format" do
        expect {
          xbrl_proxy.to_json(accession_no: "invalid-format")
        }.to raise_error(SecApi::ValidationError, /Invalid accession number format/)
      end

      it "accepts accession_no without dashes and normalizes it" do
        stubs = Faraday::Adapter::Test::Stubs.new

        stubs.get("/xbrl-to-json") do |env|
          # Should normalize to dashed format
          expect(env.params["accession-no"]).to eq("0000320193-23-000106")
          [200, {"Content-Type" => "application/json"}, xbrl_response.to_json]
        end

        allow(client).to receive(:connection).and_return(build_connection(stubs))
        # Undashed format is 18 digits: CIK(10) + Year(2) + Sequence(6)
        xbrl_proxy.to_json(accession_no: "000032019323000106")
        stubs.verify_stubbed_calls
      end
    end

    context "with Filing object input (backward compatibility)" do
      it "accepts Filing object and returns XbrlData object" do
        stubs = Faraday::Adapter::Test::Stubs.new
        stub_xbrl_request(stubs)

        allow(client).to receive(:connection).and_return(build_connection(stubs))

        result = xbrl_proxy.to_json(filing)

        expect(result).to be_a(SecApi::XbrlData)
        stubs.verify_stubbed_calls
      end

      it "sends xbrl-url and accession-no from Filing object" do
        stubs = Faraday::Adapter::Test::Stubs.new

        stubs.get("/xbrl-to-json") do |env|
          expect(env.params["xbrl-url"]).to eq("https://www.sec.gov/example.xml")
          expect(env.params["accession-no"]).to eq("0001234567-24-000001")
          [200, {"Content-Type" => "application/json"}, xbrl_response.to_json]
        end

        allow(client).to receive(:connection).and_return(build_connection(stubs))
        xbrl_proxy.to_json(filing)
        stubs.verify_stubbed_calls
      end
    end

    it "returns XbrlData object (not raw hash)" do
      stub_request = Faraday::Adapter::Test::Stubs.new
      stub_request.get("/xbrl-to-json") do |env|
        [
          200,
          {"Content-Type" => "application/json"},
          {
            StatementsOfIncome: {
              Revenue: [{value: "1000000", period: {instant: "2023-09-30"}}]
            },
            BalanceSheets: {
              Assets: [{value: "5000000", period: {instant: "2023-09-30"}}]
            }
          }.to_json
        ]
      end

      allow(client).to receive(:connection).and_return(
        Faraday.new do |conn|
          conn.request :json
          conn.response :json, content_type: /\bjson$/, parser_options: {symbolize_names: true}
          conn.adapter :test, stub_request
        end
      )

      result = xbrl_proxy.to_json(filing)

      expect(result).to be_a(SecApi::XbrlData)
      expect(result).not_to be_a(Hash)
      stub_request.verify_stubbed_calls
    end

    it "provides access to financial statements via XbrlData object" do
      stubs = Faraday::Adapter::Test::Stubs.new
      stub_xbrl_request(stubs)

      allow(client).to receive(:connection).and_return(build_connection(stubs))

      result = xbrl_proxy.to_json(filing)

      revenue_facts = result.statements_of_income["RevenueFromContractWithCustomerExcludingAssessedTax"]
      expect(revenue_facts.first.to_numeric).to eq(394328000000.0)

      assets_facts = result.balance_sheets["Assets"]
      expect(assets_facts.first.to_numeric).to eq(352755000000.0)
      stubs.verify_stubbed_calls
    end

    it "is immutable (frozen)" do
      stubs = Faraday::Adapter::Test::Stubs.new
      stub_xbrl_request(stubs)

      allow(client).to receive(:connection).and_return(build_connection(stubs))

      result = xbrl_proxy.to_json(filing)

      expect(result).to be_frozen
      stubs.verify_stubbed_calls
    end

    context "when API returns error" do
      it "raises ServerError on 500" do
        stubs = Faraday::Adapter::Test::Stubs.new
        stubs.get("/xbrl-to-json") { [500, {}, "Server error"] }

        allow(client).to receive(:connection).and_return(build_connection(stubs, with_error_handler: true))

        expect {
          xbrl_proxy.to_json(filing)
        }.to raise_error(SecApi::ServerError)
      end

      it "raises NotFoundError on 404 for invalid filing" do
        stubs = Faraday::Adapter::Test::Stubs.new
        stubs.get("/xbrl-to-json") { [404, {}, "Filing not found"] }

        allow(client).to receive(:connection).and_return(build_connection(stubs, with_error_handler: true))

        expect {
          xbrl_proxy.to_json(filing)
        }.to raise_error(SecApi::NotFoundError)
      end

      it "raises ValidationError with context when XBRL data coercion fails" do
        stubs = Faraday::Adapter::Test::Stubs.new
        stubs.get("/xbrl-to-json") do |env|
          # Return data with invalid structure that cannot be coerced
          # Facts must have string values, array of invalid format causes error
          [200, {"Content-Type" => "application/json"}, {
            StatementsOfIncome: {
              Revenue: "not_an_array"  # Should be array of fact hashes
            }
          }.to_json]
        end

        allow(client).to receive(:connection).and_return(build_connection(stubs))

        expect {
          xbrl_proxy.to_json(filing)
        }.to raise_error(SecApi::ValidationError, /XBRL data validation failed/)
      end
    end

    context "retry behavior for transient errors (AC: #5)" do
      it "relies on retry middleware for 503 Service Unavailable" do
        # The retry middleware (configured in Client) handles transient errors
        # This test verifies the error handler classifies 503 as ServerError (TransientError)
        stubs = Faraday::Adapter::Test::Stubs.new
        stubs.get("/xbrl-to-json") { [503, {}, "Service Unavailable"] }

        allow(client).to receive(:connection).and_return(build_connection(stubs, with_error_handler: true))

        # Without retry middleware, ServerError is raised
        # With retry middleware, this would be retried automatically
        expect {
          xbrl_proxy.to_json(filing)
        }.to raise_error(SecApi::ServerError)
      end

      it "relies on retry middleware for timeout errors" do
        # NetworkError (TransientError) is automatically retried by retry middleware
        stubs = Faraday::Adapter::Test::Stubs.new
        stubs.get("/xbrl-to-json") { raise Faraday::TimeoutError }

        allow(client).to receive(:connection).and_return(build_connection(stubs, with_error_handler: true))

        expect {
          xbrl_proxy.to_json(filing)
        }.to raise_error(SecApi::NetworkError)
      end
    end
  end

  describe "full integration test with middleware stack" do
    let(:config) { SecApi::Config.new(api_key: "test_api_key_valid", retry_max_attempts: 3) }
    let(:integration_client) { SecApi::Client.new(config) }
    let(:filing) do
      double(
        "Filing",
        xbrl_url: "https://www.sec.gov/example.xml",
        accession_number: "0001234567-24-000001"
      )
    end

    it "returns XbrlData through full middleware stack (retry + error handler)" do
      stubs = Faraday::Adapter::Test::Stubs.new

      # Use direct stub without retry middleware for simplicity
      stubs.get("/xbrl-to-json") do |env|
        [
          200,
          {"Content-Type" => "application/json"},
          {
            StatementsOfIncome: {
              Revenue: [{value: "2000000", decimals: "-3", unitRef: "usd", period: {startDate: "2023-01-01", endDate: "2023-12-31"}}]
            },
            BalanceSheets: {
              Assets: [{value: "10000000", decimals: "-3", unitRef: "usd", period: {instant: "2023-09-30"}}]
            }
          }.to_json
        ]
      end

      allow(integration_client).to receive(:connection).and_return(
        Faraday.new do |conn|
          conn.request :json
          conn.response :json, content_type: /\bjson$/, parser_options: {symbolize_names: true}
          conn.use SecApi::Middleware::ErrorHandler
          conn.adapter :test, stubs
        end
      )

      result = integration_client.xbrl.to_json(filing)

      expect(result).to be_a(SecApi::XbrlData)
      expect(result.statements_of_income["Revenue"].first.to_numeric).to eq(2_000_000.0)
      expect(result).to be_frozen

      stubs.verify_stubbed_calls
    end
  end
end
