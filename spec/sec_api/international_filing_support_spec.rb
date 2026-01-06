require "spec_helper"

RSpec.describe "International Filing Support", type: :feature do
  # Test coverage for Story 2.7: International Filing Support (20-F, 40-F, 6-K)
  # Verifies that international SEC form types are handled as first-class citizens.

  describe "Form Type Constants" do
    describe "SecApi::Query::DOMESTIC_FORM_TYPES" do
      it "includes common domestic form types" do
        expect(SecApi::Query::DOMESTIC_FORM_TYPES).to include("10-K", "10-Q", "8-K")
      end

      it "is frozen" do
        expect(SecApi::Query::DOMESTIC_FORM_TYPES).to be_frozen
      end
    end

    describe "SecApi::Query::INTERNATIONAL_FORM_TYPES" do
      it "includes all international form types (20-F, 40-F, 6-K)" do
        expect(SecApi::Query::INTERNATIONAL_FORM_TYPES).to contain_exactly("20-F", "40-F", "6-K")
      end

      it "is frozen" do
        expect(SecApi::Query::INTERNATIONAL_FORM_TYPES).to be_frozen
      end
    end

    describe "SecApi::Query::ALL_FORM_TYPES" do
      it "combines domestic and international form types" do
        expect(SecApi::Query::ALL_FORM_TYPES).to include("10-K", "20-F", "40-F", "6-K")
      end

      it "is frozen" do
        expect(SecApi::Query::ALL_FORM_TYPES).to be_frozen
      end
    end
  end

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

  let(:json_headers) { {"Content-Type" => "application/json"} }
  let(:empty_response) { {filings: [], total: {value: 0}}.to_json }

  describe "Form 20-F (Foreign Private Issuer Annual Reports)" do
    # AC #1: Query Form 20-F works identically to 10-K

    it "generates correct Lucene query for single 20-F form type (AC #1)" do
      stubs.post("/") do |env|
        body = JSON.parse(env.body)
        expect(body["query"]).to eq('formType:"20-F"')
        [200, json_headers, empty_response]
      end

      client.query.form_type("20-F").search
    end

    it "works with ticker filter for foreign private issuers (AC #1)" do
      stubs.post("/") do |env|
        body = JSON.parse(env.body)
        expect(body["query"]).to eq('ticker:NMR AND formType:"20-F"')
        [200, json_headers, empty_response]
      end

      client.query.ticker("NMR").form_type("20-F").search
    end
  end

  describe "Form 40-F (Canadian Issuer Annual Reports - MJDS)" do
    # AC #2: Query Form 40-F works identically to 10-K

    it "generates correct Lucene query for single 40-F form type (AC #2)" do
      stubs.post("/") do |env|
        body = JSON.parse(env.body)
        expect(body["query"]).to eq('formType:"40-F"')
        [200, json_headers, empty_response]
      end

      client.query.form_type("40-F").search
    end

    it "works with ticker filter for Canadian issuers (AC #2)" do
      stubs.post("/") do |env|
        body = JSON.parse(env.body)
        expect(body["query"]).to eq('ticker:ABX AND formType:"40-F"')
        [200, json_headers, empty_response]
      end

      client.query.ticker("ABX").form_type("40-F").search
    end
  end

  describe "Form 6-K (Foreign Private Issuer Current Reports)" do
    # AC #3: Query Form 6-K works identically to 8-K

    it "generates correct Lucene query for single 6-K form type (AC #3)" do
      stubs.post("/") do |env|
        body = JSON.parse(env.body)
        expect(body["query"]).to eq('formType:"6-K"')
        [200, json_headers, empty_response]
      end

      client.query.form_type("6-K").search
    end

    it "works with ticker filter for foreign private issuers (AC #3)" do
      stubs.post("/") do |env|
        body = JSON.parse(env.body)
        expect(body["query"]).to eq('ticker:NMR AND formType:"6-K"')
        [200, json_headers, empty_response]
      end

      client.query.ticker("NMR").form_type("6-K").search
    end
  end

  describe "Multiple International Form Types" do
    # AC #4: Query multiple international form types with OR syntax

    it "generates correct Lucene OR query for 20-F and 6-K (AC #4)" do
      stubs.post("/") do |env|
        body = JSON.parse(env.body)
        expect(body["query"]).to eq('formType:("20-F" OR "6-K")')
        [200, json_headers, empty_response]
      end

      client.query.form_type("20-F", "6-K").search
    end

    it "generates correct Lucene OR query for all international forms (AC #4)" do
      stubs.post("/") do |env|
        body = JSON.parse(env.body)
        expect(body["query"]).to eq('formType:("20-F" OR "40-F" OR "6-K")')
        [200, json_headers, empty_response]
      end

      client.query.form_type("20-F", "40-F", "6-K").search
    end

    it "treats international forms as first-class citizens with ticker filter (AC #4)" do
      stubs.post("/") do |env|
        body = JSON.parse(env.body)
        expect(body["query"]).to eq('ticker:NMR AND formType:("20-F" OR "6-K")')
        [200, json_headers, empty_response]
      end

      client.query.ticker("NMR").form_type("20-F", "6-K").search
    end
  end

  describe "Filing Object Creation from International Responses" do
    # AC #5: Filing objects are returned with the same structure as domestic filings

    def build_international_filing_hash(form_type:, ticker:, company_name:, cik:)
      {
        "id" => SecureRandom.uuid,
        "ticker" => ticker,
        "cik" => cik,
        "companyName" => company_name,
        "companyNameLong" => "#{company_name} Inc.",
        "formType" => form_type,
        "periodOfReport" => "2024-03-31",
        "filedAt" => "2024-06-28",
        "linkToTxt" => "https://sec.gov/Archives/edgar/data/#{cik}/txt",
        "linkToHtml" => "https://sec.gov/Archives/edgar/data/#{cik}/html",
        "linkToXbrl" => "https://sec.gov/Archives/edgar/data/#{cik}/xbrl",
        "linkToFilingDetails" => "https://sec.gov/cgi-bin/browse-edgar?action=getcompany&CIK=#{cik}",
        "accessionNo" => "0001193125-24-#{rand(100000..999999)}",
        "entities" => [],
        "documentFormatFiles" => [],
        "dataFiles" => []
      }
    end

    describe "Form 20-F Filing (Foreign Private Issuer)" do
      let(:nmr_20f_filing) do
        build_international_filing_hash(
          form_type: "20-F",
          ticker: "NMR",
          company_name: "Nomura Holdings",
          cik: "1163653"
        )
      end

      it "creates Filing object with correct form_type for 20-F (AC #5)" do
        response_body = {filings: [nmr_20f_filing], total: {value: 1}}.to_json

        stubs.post("/") do |_env|
          [200, json_headers, response_body]
        end

        result = client.query.ticker("NMR").form_type("20-F").search
        filing = result.first

        expect(filing).to be_a(SecApi::Objects::Filing)
        expect(filing.form_type).to eq("20-F")
        expect(filing.ticker).to eq("NMR")
        expect(filing.company_name).to eq("Nomura Holdings")
        expect(filing.cik).to eq("1163653")
      end

      it "populates all Filing attributes correctly for 20-F (AC #5)" do
        response_body = {filings: [nmr_20f_filing], total: {value: 1}}.to_json

        stubs.post("/") do |_env|
          [200, json_headers, response_body]
        end

        result = client.query.ticker("NMR").form_type("20-F").search
        filing = result.first

        expect(filing.period_of_report).to eq("2024-03-31")
        expect(filing.filed_at).to eq(Date.new(2024, 6, 28))
        expect(filing.txt_url).to include("sec.gov")
        expect(filing.html_url).to include("sec.gov")
        expect(filing.xbrl_url).to include("sec.gov")
        expect(filing.filing_details_url).to include("sec.gov")
        expect(filing.accession_number).to match(/0001193125-24-\d+/)
      end
    end

    describe "Form 40-F Filing (Canadian Issuer - MJDS)" do
      let(:abx_40f_filing) do
        build_international_filing_hash(
          form_type: "40-F",
          ticker: "ABX",
          company_name: "Barrick Gold",
          cik: "756894"
        )
      end

      it "creates Filing object with correct form_type for 40-F (AC #5)" do
        response_body = {filings: [abx_40f_filing], total: {value: 1}}.to_json

        stubs.post("/") do |_env|
          [200, json_headers, response_body]
        end

        result = client.query.ticker("ABX").form_type("40-F").search
        filing = result.first

        expect(filing).to be_a(SecApi::Objects::Filing)
        expect(filing.form_type).to eq("40-F")
        expect(filing.ticker).to eq("ABX")
        expect(filing.company_name).to eq("Barrick Gold")
        expect(filing.cik).to eq("756894")
      end

      it "populates all Filing attributes correctly for 40-F (AC #5)" do
        response_body = {filings: [abx_40f_filing], total: {value: 1}}.to_json

        stubs.post("/") do |_env|
          [200, json_headers, response_body]
        end

        result = client.query.ticker("ABX").form_type("40-F").search
        filing = result.first

        expect(filing.period_of_report).to eq("2024-03-31")
        expect(filing.filed_at).to eq(Date.new(2024, 6, 28))
        expect(filing.accession_number).to match(/0001193125-24-\d+/)
        expect(filing.entities).to eq([])
        expect(filing.documents).to eq([])
        expect(filing.data_files).to eq([])
      end
    end

    describe "Form 6-K Filing (Foreign Current Report)" do
      let(:nmr_6k_filing) do
        build_international_filing_hash(
          form_type: "6-K",
          ticker: "NMR",
          company_name: "Nomura Holdings",
          cik: "1163653"
        )
      end

      it "creates Filing object with correct form_type for 6-K (AC #5)" do
        response_body = {filings: [nmr_6k_filing], total: {value: 1}}.to_json

        stubs.post("/") do |_env|
          [200, json_headers, response_body]
        end

        result = client.query.ticker("NMR").form_type("6-K").search
        filing = result.first

        expect(filing).to be_a(SecApi::Objects::Filing)
        expect(filing.form_type).to eq("6-K")
        expect(filing.ticker).to eq("NMR")
        expect(filing.company_name).to eq("Nomura Holdings")
      end

      it "populates all Filing attributes correctly for 6-K (AC #5)" do
        response_body = {filings: [nmr_6k_filing], total: {value: 1}}.to_json

        stubs.post("/") do |_env|
          [200, json_headers, response_body]
        end

        result = client.query.ticker("NMR").form_type("6-K").search
        filing = result.first

        expect(filing.period_of_report).to eq("2024-03-31")
        expect(filing.filed_at).to eq(Date.new(2024, 6, 28))
        expect(filing.txt_url).to include("sec.gov")
        expect(filing.accession_number).to match(/0001193125-24-\d+/)
      end
    end

    describe "Multiple International Filings in Response" do
      it "handles mixed international form types in single response (AC #4, #5)" do
        filings = [
          build_international_filing_hash(form_type: "20-F", ticker: "NMR", company_name: "Nomura Holdings", cik: "1163653"),
          build_international_filing_hash(form_type: "6-K", ticker: "NMR", company_name: "Nomura Holdings", cik: "1163653")
        ]
        response_body = {filings: filings, total: {value: 2}}.to_json

        stubs.post("/") do |_env|
          [200, json_headers, response_body]
        end

        result = client.query.ticker("NMR").form_type("20-F", "6-K").search

        expect(result.count).to eq(2)
        expect(result.map(&:form_type)).to contain_exactly("20-F", "6-K")
        result.each do |filing|
          expect(filing).to be_a(SecApi::Objects::Filing)
          expect(filing.ticker).to eq("NMR")
        end
      end
    end
  end

  describe "Symbol Input Support" do
    # Verifies form_type accepts symbols (converted via .to_s)

    it "accepts symbol input for international form types" do
      stubs.post("/") do |env|
        body = JSON.parse(env.body)
        expect(body["query"]).to eq('formType:"20-F"')
        [200, json_headers, empty_response]
      end

      client.query.form_type(:"20-F").search
    end
  end

  describe "Case Sensitivity" do
    # Verifies that form types are case-sensitive as documented

    it "treats form types as case-sensitive (20-F vs 20-f)" do
      stubs.post("/") do |env|
        body = JSON.parse(env.body)
        # Lowercase "20-f" should be passed through as-is, not normalized
        expect(body["query"]).to eq('formType:"20-f"')
        [200, json_headers, empty_response]
      end

      client.query.form_type("20-f").search
    end

    it "preserves exact case for mixed case input" do
      stubs.post("/") do |env|
        body = JSON.parse(env.body)
        expect(body["query"]).to eq('formType:("20-F" OR "20-f")')
        [200, json_headers, empty_response]
      end

      client.query.form_type("20-F", "20-f").search
    end
  end

  describe "Mixed Domestic and International Form Types" do
    # Verifies that domestic and international forms can be combined seamlessly

    it "generates correct Lucene OR query for domestic 10-K and international 20-F" do
      stubs.post("/") do |env|
        body = JSON.parse(env.body)
        expect(body["query"]).to eq('formType:("10-K" OR "20-F")')
        [200, json_headers, empty_response]
      end

      client.query.form_type("10-K", "20-F").search
    end

    it "generates correct query for all annual report types (10-K, 20-F, 40-F)" do
      stubs.post("/") do |env|
        body = JSON.parse(env.body)
        expect(body["query"]).to eq('formType:("10-K" OR "20-F" OR "40-F")')
        [200, json_headers, empty_response]
      end

      client.query.form_type("10-K", "20-F", "40-F").search
    end

    it "generates correct query for all current report types (8-K, 6-K)" do
      stubs.post("/") do |env|
        body = JSON.parse(env.body)
        expect(body["query"]).to eq('formType:("8-K" OR "6-K")')
        [200, json_headers, empty_response]
      end

      client.query.form_type("8-K", "6-K").search
    end

    it "handles complex mixed query with date range" do
      stubs.post("/") do |env|
        body = JSON.parse(env.body)
        expect(body["query"]).to eq('ticker:NMR AND formType:("10-K" OR "20-F") AND filedAt:[2020-01-01 TO 2024-12-31]')
        [200, json_headers, empty_response]
      end

      client.query
        .ticker("NMR")
        .form_type("10-K", "20-F")
        .date_range(from: "2020-01-01", to: "2024-12-31")
        .search
    end
  end
end
