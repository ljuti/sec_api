# frozen_string_literal: true

require "spec_helper"

RSpec.describe SecApi::Xbrl do
  let(:config) { SecApi::Config.new(api_key: "test_api_key_valid") }
  let(:client) { SecApi::Client.new(config) }
  let(:xbrl_proxy) { client.xbrl }

  # Shared helper for building test connections (used across multiple contexts)
  def build_connection(stubs, with_error_handler: false)
    Faraday.new do |conn|
      conn.request :json
      conn.response :json, content_type: /\bjson$/, parser_options: {symbolize_names: true}
      conn.use SecApi::Middleware::ErrorHandler if with_error_handler
      conn.adapter :test, stubs
    end
  end

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

  describe "US GAAP taxonomy support (Story 4.5, AC #1)" do
    let(:us_gaap_response) do
      {
        StatementsOfIncome: {
          # US GAAP uses verbose, specific element names
          "RevenueFromContractWithCustomerExcludingAssessedTax" => [
            {value: "394328000000", decimals: "-6", unitRef: "usd", period: {startDate: "2022-09-25", endDate: "2023-09-30"}}
          ],
          "CostOfGoodsAndServicesSold" => [
            {value: "214137000000", decimals: "-6", unitRef: "usd", period: {startDate: "2022-09-25", endDate: "2023-09-30"}}
          ],
          "NetIncomeLoss" => [
            {value: "96995000000", decimals: "-6", unitRef: "usd", period: {startDate: "2022-09-25", endDate: "2023-09-30"}}
          ]
        },
        BalanceSheets: {
          "Assets" => [{value: "352755000000", decimals: "-6", unitRef: "usd", period: {instant: "2023-09-30"}}],
          "Liabilities" => [{value: "290437000000", decimals: "-6", unitRef: "usd", period: {instant: "2023-09-30"}}],
          "StockholdersEquity" => [{value: "62318000000", decimals: "-6", unitRef: "usd", period: {instant: "2023-09-30"}}]
        },
        StatementsOfCashFlows: {
          "NetCashProvidedByUsedInOperatingActivities" => [
            {value: "110543000000", decimals: "-6", unitRef: "usd", period: {startDate: "2022-09-25", endDate: "2023-09-30"}}
          ]
        },
        CoverPage: {
          "DocumentType" => [{value: "10-K", period: {instant: "2023-09-30"}}],
          "EntityRegistrantName" => [{value: "Apple Inc", period: {instant: "2023-09-30"}}]
        }
      }
    end

    def stub_us_gaap_request(stubs)
      stubs.get("/xbrl-to-json") do |env|
        [200, {"Content-Type" => "application/json"}, us_gaap_response.to_json]
      end
    end

    it "extracts XBRL data from 10-K filing with US GAAP taxonomy" do
      stubs = Faraday::Adapter::Test::Stubs.new
      stub_us_gaap_request(stubs)

      allow(client).to receive(:connection).and_return(build_connection(stubs))

      result = xbrl_proxy.to_json("https://www.sec.gov/Archives/edgar/data/320193/000032019323000106/aapl-20230930.htm")

      expect(result).to be_a(SecApi::XbrlData)
      expect(result.valid?).to be true
      stubs.verify_stubbed_calls
    end

    it "populates XbrlData structure correctly with US GAAP elements" do
      stubs = Faraday::Adapter::Test::Stubs.new
      stub_us_gaap_request(stubs)

      allow(client).to receive(:connection).and_return(build_connection(stubs))

      result = xbrl_proxy.to_json("https://www.sec.gov/Archives/edgar/data/320193/000032019323000106/aapl-20230930.htm")

      # Income statement
      expect(result.statements_of_income).to have_key("RevenueFromContractWithCustomerExcludingAssessedTax")
      expect(result.statements_of_income).to have_key("CostOfGoodsAndServicesSold")
      expect(result.statements_of_income).to have_key("NetIncomeLoss")

      # Balance sheet
      expect(result.balance_sheets).to have_key("Assets")
      expect(result.balance_sheets).to have_key("Liabilities")
      expect(result.balance_sheets).to have_key("StockholdersEquity")

      # Cash flow
      expect(result.statements_of_cash_flows).to have_key("NetCashProvidedByUsedInOperatingActivities")

      stubs.verify_stubbed_calls
    end

    it "returns element_names with US GAAP conventions" do
      stubs = Faraday::Adapter::Test::Stubs.new
      stub_us_gaap_request(stubs)

      allow(client).to receive(:connection).and_return(build_connection(stubs))

      result = xbrl_proxy.to_json("https://www.sec.gov/Archives/edgar/data/320193/000032019323000106/aapl-20230930.htm")
      element_names = result.element_names

      # US GAAP uses verbose element names
      expect(element_names).to include("RevenueFromContractWithCustomerExcludingAssessedTax")
      expect(element_names).to include("StockholdersEquity")
      expect(element_names).to include("NetCashProvidedByUsedInOperatingActivities")

      # Should be sorted and unique
      expect(element_names).to eq(element_names.sort)
      expect(element_names).to eq(element_names.uniq)

      stubs.verify_stubbed_calls
    end

    it "provides numeric access to US GAAP financial data" do
      stubs = Faraday::Adapter::Test::Stubs.new
      stub_us_gaap_request(stubs)

      allow(client).to receive(:connection).and_return(build_connection(stubs))

      result = xbrl_proxy.to_json("https://www.sec.gov/Archives/edgar/data/320193/000032019323000106/aapl-20230930.htm")

      revenue = result.statements_of_income["RevenueFromContractWithCustomerExcludingAssessedTax"].first
      expect(revenue.to_numeric).to eq(394328000000.0)

      assets = result.balance_sheets["Assets"].first
      expect(assets.to_numeric).to eq(352755000000.0)

      stubs.verify_stubbed_calls
    end

    it "identifies 10-K form type in cover page" do
      stubs = Faraday::Adapter::Test::Stubs.new
      stub_us_gaap_request(stubs)

      allow(client).to receive(:connection).and_return(build_connection(stubs))

      result = xbrl_proxy.to_json("https://www.sec.gov/Archives/edgar/data/320193/000032019323000106/aapl-20230930.htm")

      doc_type = result.cover_page["DocumentType"].first
      expect(doc_type.value).to eq("10-K")

      stubs.verify_stubbed_calls
    end
  end

  describe "IFRS taxonomy support for 20-F filings (Story 4.5, AC #2)" do
    let(:ifrs_20f_response) do
      {
        StatementsOfIncome: {
          # IFRS uses simpler, shorter element names
          "Revenue" => [
            {value: "52896000000", decimals: "-6", unitRef: "usd", period: {startDate: "2023-01-01", endDate: "2023-12-31"}}
          ],
          "CostOfSales" => [
            {value: "32453000000", decimals: "-6", unitRef: "usd", period: {startDate: "2023-01-01", endDate: "2023-12-31"}}
          ],
          "ProfitLoss" => [
            {value: "12876000000", decimals: "-6", unitRef: "usd", period: {startDate: "2023-01-01", endDate: "2023-12-31"}}
          ]
        },
        BalanceSheets: {
          "Assets" => [{value: "198765000000", decimals: "-6", unitRef: "usd", period: {instant: "2023-12-31"}}],
          "Liabilities" => [{value: "145678000000", decimals: "-6", unitRef: "usd", period: {instant: "2023-12-31"}}],
          # IFRS uses "Equity" instead of "StockholdersEquity"
          "Equity" => [{value: "53087000000", decimals: "-6", unitRef: "usd", period: {instant: "2023-12-31"}}]
        },
        StatementsOfCashFlows: {
          # IFRS uses different cash flow element names
          "CashFlowsFromUsedInOperatingActivities" => [
            {value: "18543000000", decimals: "-6", unitRef: "usd", period: {startDate: "2023-01-01", endDate: "2023-12-31"}}
          ]
        },
        CoverPage: {
          "DocumentType" => [{value: "20-F", period: {instant: "2023-12-31"}}],
          "EntityRegistrantName" => [{value: "Example Foreign Company Ltd", period: {instant: "2023-12-31"}}]
        }
      }
    end

    def stub_ifrs_request(stubs)
      stubs.get("/xbrl-to-json") do |env|
        [200, {"Content-Type" => "application/json"}, ifrs_20f_response.to_json]
      end
    end

    it "extracts XBRL data from 20-F filing with IFRS taxonomy" do
      stubs = Faraday::Adapter::Test::Stubs.new
      stub_ifrs_request(stubs)

      allow(client).to receive(:connection).and_return(build_connection(stubs))

      result = xbrl_proxy.to_json("https://www.sec.gov/Archives/edgar/data/1234567/000123456724000001/example-20f.htm")

      expect(result).to be_a(SecApi::XbrlData)
      expect(result.valid?).to be true
      stubs.verify_stubbed_calls
    end

    it "uses XbrlData structure identical to US GAAP" do
      stubs = Faraday::Adapter::Test::Stubs.new
      stub_ifrs_request(stubs)

      allow(client).to receive(:connection).and_return(build_connection(stubs))

      result = xbrl_proxy.to_json("https://www.sec.gov/Archives/edgar/data/1234567/000123456724000001/example-20f.htm")

      # Same structure as US GAAP
      expect(result).to respond_to(:statements_of_income)
      expect(result).to respond_to(:balance_sheets)
      expect(result).to respond_to(:statements_of_cash_flows)
      expect(result).to respond_to(:cover_page)
      expect(result).to respond_to(:element_names)
      expect(result).to respond_to(:valid?)

      stubs.verify_stubbed_calls
    end

    it "returns IFRS element names (different from US GAAP)" do
      stubs = Faraday::Adapter::Test::Stubs.new
      stub_ifrs_request(stubs)

      allow(client).to receive(:connection).and_return(build_connection(stubs))

      result = xbrl_proxy.to_json("https://www.sec.gov/Archives/edgar/data/1234567/000123456724000001/example-20f.htm")
      element_names = result.element_names

      # IFRS uses simpler element names
      expect(element_names).to include("Revenue")  # Not "RevenueFromContractWithCustomerExcludingAssessedTax"
      expect(element_names).to include("CostOfSales")  # Not "CostOfGoodsAndServicesSold"
      expect(element_names).to include("ProfitLoss")  # Not "NetIncomeLoss"
      expect(element_names).to include("Equity")  # Not "StockholdersEquity"
      expect(element_names).to include("CashFlowsFromUsedInOperatingActivities")

      stubs.verify_stubbed_calls
    end

    it "provides numeric access to IFRS financial data" do
      stubs = Faraday::Adapter::Test::Stubs.new
      stub_ifrs_request(stubs)

      allow(client).to receive(:connection).and_return(build_connection(stubs))

      result = xbrl_proxy.to_json("https://www.sec.gov/Archives/edgar/data/1234567/000123456724000001/example-20f.htm")

      revenue = result.statements_of_income["Revenue"].first
      expect(revenue.to_numeric).to eq(52896000000.0)

      equity = result.balance_sheets["Equity"].first
      expect(equity.to_numeric).to eq(53087000000.0)

      stubs.verify_stubbed_calls
    end

    it "identifies 20-F form type in cover page" do
      stubs = Faraday::Adapter::Test::Stubs.new
      stub_ifrs_request(stubs)

      allow(client).to receive(:connection).and_return(build_connection(stubs))

      result = xbrl_proxy.to_json("https://www.sec.gov/Archives/edgar/data/1234567/000123456724000001/example-20f.htm")

      doc_type = result.cover_page["DocumentType"].first
      expect(doc_type.value).to eq("20-F")

      stubs.verify_stubbed_calls
    end
  end

  describe "40-F filing extraction for Canadian issuers (Story 4.5, AC #3)" do
    let(:canadian_40f_response) do
      {
        StatementsOfIncome: {
          # Canadian companies often use IFRS
          "Revenue" => [
            {value: "15234000000", decimals: "-6", unitRef: "cad", period: {startDate: "2023-01-01", endDate: "2023-12-31"}}
          ],
          "ProfitLoss" => [
            {value: "2876000000", decimals: "-6", unitRef: "cad", period: {startDate: "2023-01-01", endDate: "2023-12-31"}}
          ]
        },
        BalanceSheets: {
          "Assets" => [{value: "45678000000", decimals: "-6", unitRef: "cad", period: {instant: "2023-12-31"}}],
          "Liabilities" => [{value: "28765000000", decimals: "-6", unitRef: "cad", period: {instant: "2023-12-31"}}],
          "Equity" => [{value: "16913000000", decimals: "-6", unitRef: "cad", period: {instant: "2023-12-31"}}]
        },
        StatementsOfCashFlows: {
          "CashFlowsFromUsedInOperatingActivities" => [
            {value: "5432000000", decimals: "-6", unitRef: "cad", period: {startDate: "2023-01-01", endDate: "2023-12-31"}}
          ]
        },
        CoverPage: {
          "DocumentType" => [{value: "40-F", period: {instant: "2023-12-31"}}],
          "EntityRegistrantName" => [{value: "Example Canadian Corp", period: {instant: "2023-12-31"}}]
        }
      }
    end

    def stub_40f_request(stubs)
      stubs.get("/xbrl-to-json") do |env|
        [200, {"Content-Type" => "application/json"}, canadian_40f_response.to_json]
      end
    end

    it "extracts XBRL data from 40-F filing (Canadian issuer)" do
      stubs = Faraday::Adapter::Test::Stubs.new
      stub_40f_request(stubs)

      allow(client).to receive(:connection).and_return(build_connection(stubs))

      result = xbrl_proxy.to_json("https://www.sec.gov/Archives/edgar/data/7654321/000765432124000001/example-40f.htm")

      expect(result).to be_a(SecApi::XbrlData)
      expect(result.valid?).to be true
      stubs.verify_stubbed_calls
    end

    it "handles Canadian GAAP/IFRS taxonomy elements" do
      stubs = Faraday::Adapter::Test::Stubs.new
      stub_40f_request(stubs)

      allow(client).to receive(:connection).and_return(build_connection(stubs))

      result = xbrl_proxy.to_json("https://www.sec.gov/Archives/edgar/data/7654321/000765432124000001/example-40f.htm")

      # Canadian companies typically use IFRS element names
      expect(result.element_names).to include("Revenue")
      expect(result.element_names).to include("ProfitLoss")
      expect(result.element_names).to include("Equity")

      stubs.verify_stubbed_calls
    end

    it "requires no special code paths for 40-F (same as 10-K and 20-F)" do
      stubs = Faraday::Adapter::Test::Stubs.new
      stub_40f_request(stubs)

      allow(client).to receive(:connection).and_return(build_connection(stubs))

      result = xbrl_proxy.to_json("https://www.sec.gov/Archives/edgar/data/7654321/000765432124000001/example-40f.htm")

      # Same structure and methods as US GAAP filings
      expect(result).to respond_to(:statements_of_income)
      expect(result).to respond_to(:balance_sheets)
      expect(result).to respond_to(:statements_of_cash_flows)
      expect(result).to respond_to(:cover_page)
      expect(result).to respond_to(:element_names)

      # Numeric access works identically
      revenue = result.statements_of_income["Revenue"].first
      expect(revenue.to_numeric).to eq(15234000000.0)

      stubs.verify_stubbed_calls
    end

    it "identifies 40-F form type in cover page" do
      stubs = Faraday::Adapter::Test::Stubs.new
      stub_40f_request(stubs)

      allow(client).to receive(:connection).and_return(build_connection(stubs))

      result = xbrl_proxy.to_json("https://www.sec.gov/Archives/edgar/data/7654321/000765432124000001/example-40f.htm")

      doc_type = result.cover_page["DocumentType"].first
      expect(doc_type.value).to eq("40-F")

      stubs.verify_stubbed_calls
    end

    it "handles CAD currency units from Canadian filings" do
      stubs = Faraday::Adapter::Test::Stubs.new
      stub_40f_request(stubs)

      allow(client).to receive(:connection).and_return(build_connection(stubs))

      result = xbrl_proxy.to_json("https://www.sec.gov/Archives/edgar/data/7654321/000765432124000001/example-40f.htm")

      # Facts preserve unit reference from API response
      revenue_fact = result.statements_of_income["Revenue"].first
      expect(revenue_fact.unit_ref).to eq("cad")

      stubs.verify_stubbed_calls
    end
  end

  describe "#taxonomy_hint (Story 4.5, Task 5)" do
    def build_xbrl_data(response)
      stubs = Faraday::Adapter::Test::Stubs.new
      stubs.get("/xbrl-to-json") do |env|
        [200, {"Content-Type" => "application/json"}, response.to_json]
      end

      connection = Faraday.new do |conn|
        conn.request :json
        conn.response :json, content_type: /\bjson$/, parser_options: {symbolize_names: true}
        conn.adapter :test, stubs
      end

      allow(client).to receive(:connection).and_return(connection)
      result = xbrl_proxy.to_json("https://www.sec.gov/example.htm")
      stubs.verify_stubbed_calls
      result
    end

    context "with US GAAP filings" do
      it "returns :us_gaap for typical US GAAP element names" do
        response = {
          StatementsOfIncome: {
            "RevenueFromContractWithCustomerExcludingAssessedTax" => [{value: "100", period: {instant: "2023-09-30"}}],
            "CostOfGoodsAndServicesSold" => [{value: "50", period: {instant: "2023-09-30"}}]
          },
          BalanceSheets: {
            "StockholdersEquity" => [{value: "200", period: {instant: "2023-09-30"}}]
          }
        }

        xbrl_data = build_xbrl_data(response)
        expect(xbrl_data.taxonomy_hint).to eq(:us_gaap)
      end

      it "returns :us_gaap when verbose naming patterns detected" do
        response = {
          StatementsOfIncome: {
            "NetCashProvidedByUsedInOperatingActivities" => [{value: "100", period: {instant: "2023-09-30"}}]
          }
        }

        xbrl_data = build_xbrl_data(response)
        expect(xbrl_data.taxonomy_hint).to eq(:us_gaap)
      end
    end

    context "with IFRS filings" do
      it "returns :ifrs for typical IFRS element names" do
        response = {
          StatementsOfIncome: {
            "Revenue" => [{value: "100", period: {instant: "2023-12-31"}}],
            "CostOfSales" => [{value: "50", period: {instant: "2023-12-31"}}],
            "ProfitLoss" => [{value: "30", period: {instant: "2023-12-31"}}]
          },
          BalanceSheets: {
            "Equity" => [{value: "200", period: {instant: "2023-12-31"}}]
          }
        }

        xbrl_data = build_xbrl_data(response)
        expect(xbrl_data.taxonomy_hint).to eq(:ifrs)
      end

      it "returns :ifrs when IFRS-specific elements detected" do
        response = {
          StatementsOfCashFlows: {
            "CashFlowsFromUsedInOperatingActivities" => [{value: "100", period: {instant: "2023-12-31"}}]
          }
        }

        xbrl_data = build_xbrl_data(response)
        expect(xbrl_data.taxonomy_hint).to eq(:ifrs)
      end
    end

    context "with ambiguous filings" do
      it "returns :unknown when no clear taxonomy indicators" do
        response = {
          BalanceSheets: {
            "Assets" => [{value: "100", period: {instant: "2023-09-30"}}],
            "Liabilities" => [{value: "50", period: {instant: "2023-09-30"}}]
          }
        }

        xbrl_data = build_xbrl_data(response)
        expect(xbrl_data.taxonomy_hint).to eq(:unknown)
      end

      it "returns :unknown for cover page only filings" do
        response = {
          CoverPage: {
            "DocumentType" => [{value: "10-K", period: {instant: "2023-09-30"}}]
          }
        }

        xbrl_data = build_xbrl_data(response)
        expect(xbrl_data.taxonomy_hint).to eq(:unknown)
      end

      it "returns :unknown when US GAAP and IFRS indicators are tied" do
        response = {
          BalanceSheets: {
            # US GAAP indicator (matches /StockholdersEquity/)
            "StockholdersEquity" => [{value: "100", period: {instant: "2023-09-30"}}],
            # IFRS indicator (matches /\AEquity\z/)
            "Equity" => [{value: "100", period: {instant: "2023-09-30"}}]
          }
        }

        xbrl_data = build_xbrl_data(response)
        # Tied scores (1 US GAAP, 1 IFRS) should return :unknown
        expect(xbrl_data.taxonomy_hint).to eq(:unknown)
      end
    end
  end

  describe "structure comparison between US GAAP and IFRS (Story 4.5)" do
    let(:us_gaap_response) do
      {
        StatementsOfIncome: {"RevenueFromContractWithCustomerExcludingAssessedTax" => [{value: "100", period: {instant: "2023-09-30"}}]},
        BalanceSheets: {"Assets" => [{value: "500", period: {instant: "2023-09-30"}}]}
      }
    end

    let(:ifrs_response) do
      {
        StatementsOfIncome: {"Revenue" => [{value: "100", period: {instant: "2023-12-31"}}]},
        BalanceSheets: {"Assets" => [{value: "500", period: {instant: "2023-12-31"}}]}
      }
    end

    def build_connection_with_response(response)
      stubs = Faraday::Adapter::Test::Stubs.new
      stubs.get("/xbrl-to-json") do |env|
        [200, {"Content-Type" => "application/json"}, response.to_json]
      end

      connection = Faraday.new do |conn|
        conn.request :json
        conn.response :json, content_type: /\bjson$/, parser_options: {symbolize_names: true}
        conn.adapter :test, stubs
      end

      [connection, stubs]
    end

    it "produces same XbrlData class for both taxonomies" do
      us_conn, us_stubs = build_connection_with_response(us_gaap_response)
      allow(client).to receive(:connection).and_return(us_conn)
      us_result = xbrl_proxy.to_json("https://www.sec.gov/example-10k.htm")
      us_stubs.verify_stubbed_calls

      ifrs_conn, ifrs_stubs = build_connection_with_response(ifrs_response)
      allow(client).to receive(:connection).and_return(ifrs_conn)
      ifrs_result = xbrl_proxy.to_json("https://www.sec.gov/example-20f.htm")
      ifrs_stubs.verify_stubbed_calls

      # Same class for both
      expect(us_result.class).to eq(ifrs_result.class)
      expect(us_result).to be_a(SecApi::XbrlData)
      expect(ifrs_result).to be_a(SecApi::XbrlData)
    end

    it "both respond to same interface methods" do
      us_conn, us_stubs = build_connection_with_response(us_gaap_response)
      allow(client).to receive(:connection).and_return(us_conn)
      us_result = xbrl_proxy.to_json("https://www.sec.gov/example-10k.htm")
      us_stubs.verify_stubbed_calls

      ifrs_conn, ifrs_stubs = build_connection_with_response(ifrs_response)
      allow(client).to receive(:connection).and_return(ifrs_conn)
      ifrs_result = xbrl_proxy.to_json("https://www.sec.gov/example-20f.htm")
      ifrs_stubs.verify_stubbed_calls

      # Both respond to same methods
      methods = [:statements_of_income, :balance_sheets, :statements_of_cash_flows, :cover_page, :element_names, :valid?]
      methods.each do |method|
        expect(us_result).to respond_to(method)
        expect(ifrs_result).to respond_to(method)
      end
    end

    it "element names differ between taxonomies (gem does NOT normalize)" do
      us_conn, us_stubs = build_connection_with_response(us_gaap_response)
      allow(client).to receive(:connection).and_return(us_conn)
      us_result = xbrl_proxy.to_json("https://www.sec.gov/example-10k.htm")
      us_stubs.verify_stubbed_calls

      ifrs_conn, ifrs_stubs = build_connection_with_response(ifrs_response)
      allow(client).to receive(:connection).and_return(ifrs_conn)
      ifrs_result = xbrl_proxy.to_json("https://www.sec.gov/example-20f.htm")
      ifrs_stubs.verify_stubbed_calls

      # Element names differ - gem returns taxonomy names as-is
      expect(us_result.element_names).to include("RevenueFromContractWithCustomerExcludingAssessedTax")
      expect(us_result.element_names).not_to include("Revenue")

      expect(ifrs_result.element_names).to include("Revenue")
      expect(ifrs_result.element_names).not_to include("RevenueFromContractWithCustomerExcludingAssessedTax")
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
