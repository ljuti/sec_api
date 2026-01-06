require "spec_helper"

RSpec.describe SecApi::Collections::Filings do
  describe "Enumerable interface" do
    let(:filings_data) do
      {
        filings: [
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
            linkToTxt: "https://example.com/1.txt",
            linkToHtml: "https://example.com/1.html",
            linkToXbrl: "https://example.com/1.xbrl",
            linkToFilingDetails: "https://example.com/1",
            entities: [],
            documentFormatFiles: [],
            dataFiles: []
          },
          {
            id: "2",
            accessionNo: "0001193125-24-001235",
            ticker: "MSFT",
            cik: "0000789019",
            formType: "10-Q",
            filedAt: "2024-01-16",
            companyName: "Microsoft Corp",
            companyNameLong: "Microsoft Corporation",
            periodOfReport: "2023-12-31",
            linkToTxt: "https://example.com/2.txt",
            linkToHtml: "https://example.com/2.html",
            linkToXbrl: "https://example.com/2.xbrl",
            linkToFilingDetails: "https://example.com/2",
            entities: [],
            documentFormatFiles: [],
            dataFiles: []
          }
        ],
        next_cursor: "cursor_abc123",
        total: 42
      }
    end

    let(:collection) { described_class.new(filings_data) }

    it "includes Enumerable module" do
      expect(described_class.ancestors).to include(Enumerable)
    end

    it "implements #each" do
      expect(collection).to respond_to(:each)
    end

    it "yields Filing objects in each iteration" do
      collection.each do |filing|
        expect(filing).to be_a(SecApi::Objects::Filing)
      end
    end

    it "supports Enumerable methods like #map" do
      tickers = collection.map(&:ticker)
      expect(tickers).to eq(["AAPL", "MSFT"])
    end

    it "supports Enumerable methods like #select" do
      ten_ks = collection.select { |f| f.form_type == "10-K" }
      expect(ten_ks.length).to eq(1)
      expect(ten_ks.first.ticker).to eq("AAPL")
    end

    it "supports #first to get first Filing" do
      expect(collection.first).to be_a(SecApi::Objects::Filing)
      expect(collection.first.ticker).to eq("AAPL")
    end

    it "supports #to_a to convert to array of Filings" do
      array = collection.to_a
      expect(array).to be_an(Array)
      expect(array.size).to eq(2)
      expect(array).to all(be_a(SecApi::Objects::Filing))
    end
  end

  describe "#count (total from API metadata)" do
    context "when total is an object with value key (API format)" do
      let(:filings_data) do
        {
          filings: [
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
              linkToTxt: "https://example.com/1.txt",
              linkToHtml: "https://example.com/1.html",
              linkToXbrl: "https://example.com/1.xbrl",
              linkToFilingDetails: "https://example.com/1",
              entities: [],
              documentFormatFiles: [],
              dataFiles: []
            }
          ],
          total: {value: 1250, relation: "eq"}
        }
      end

      let(:collection) { described_class.new(filings_data) }

      it "returns the value from API metadata total object" do
        expect(collection.count).to eq(1250)
      end

      it "returns total results available, not just current page size" do
        expect(collection.count).not_to eq(1)
        expect(collection.count).to eq(1250)
      end
    end

    context "when total is an integer (simplified format)" do
      let(:filings_data) do
        {
          filings: [
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
              linkToTxt: "https://example.com/1.txt",
              linkToHtml: "https://example.com/1.html",
              linkToXbrl: "https://example.com/1.xbrl",
              linkToFilingDetails: "https://example.com/1",
              entities: [],
              documentFormatFiles: [],
              dataFiles: []
            }
          ],
          total: 500
        }
      end

      let(:collection) { described_class.new(filings_data) }

      it "returns the integer total from API metadata" do
        expect(collection.count).to eq(500)
      end
    end

    context "when total is nil or missing" do
      let(:filings_data) do
        {
          filings: [
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
              linkToTxt: "https://example.com/1.txt",
              linkToHtml: "https://example.com/1.html",
              linkToXbrl: "https://example.com/1.xbrl",
              linkToFilingDetails: "https://example.com/1",
              entities: [],
              documentFormatFiles: [],
              dataFiles: []
            },
            {
              id: "2",
              accessionNo: "0001193125-24-001235",
              ticker: "MSFT",
              cik: "0000789019",
              formType: "10-Q",
              filedAt: "2024-01-16",
              companyName: "Microsoft Corp",
              companyNameLong: "Microsoft Corporation",
              periodOfReport: "2023-12-31",
              linkToTxt: "https://example.com/2.txt",
              linkToHtml: "https://example.com/2.html",
              linkToXbrl: "https://example.com/2.xbrl",
              linkToFilingDetails: "https://example.com/2",
              entities: [],
              documentFormatFiles: [],
              dataFiles: []
            }
          ]
        }
      end

      let(:collection) { described_class.new(filings_data) }

      it "falls back to current page size" do
        expect(collection.count).to eq(2)
      end
    end

    context "when called with a block (filtering)" do
      let(:filings_data) do
        {
          filings: [
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
              linkToTxt: "https://example.com/1.txt",
              linkToHtml: "https://example.com/1.html",
              linkToXbrl: "https://example.com/1.xbrl",
              linkToFilingDetails: "https://example.com/1",
              entities: [],
              documentFormatFiles: [],
              dataFiles: []
            },
            {
              id: "2",
              accessionNo: "0001193125-24-001235",
              ticker: "MSFT",
              cik: "0000789019",
              formType: "10-Q",
              filedAt: "2024-01-16",
              companyName: "Microsoft Corp",
              companyNameLong: "Microsoft Corporation",
              periodOfReport: "2023-12-31",
              linkToTxt: "https://example.com/2.txt",
              linkToHtml: "https://example.com/2.html",
              linkToXbrl: "https://example.com/2.xbrl",
              linkToFilingDetails: "https://example.com/2",
              entities: [],
              documentFormatFiles: [],
              dataFiles: []
            },
            {
              id: "3",
              accessionNo: "0001193125-24-001236",
              ticker: "GOOGL",
              cik: "0001652044",
              formType: "10-K",
              filedAt: "2024-01-17",
              companyName: "Alphabet Inc",
              companyNameLong: "Alphabet Inc.",
              periodOfReport: "2023-12-31",
              linkToTxt: "https://example.com/3.txt",
              linkToHtml: "https://example.com/3.html",
              linkToXbrl: "https://example.com/3.xbrl",
              linkToFilingDetails: "https://example.com/3",
              entities: [],
              documentFormatFiles: [],
              dataFiles: []
            }
          ],
          total: {value: 5000, relation: "eq"}
        }
      end

      let(:collection) { described_class.new(filings_data) }

      it "delegates to Enumerable#count and counts matching items in current page" do
        count_10k = collection.count { |f| f.form_type == "10-K" }
        expect(count_10k).to eq(2)
      end

      it "returns 0 when no items match the block condition" do
        count_8k = collection.count { |f| f.form_type == "8-K" }
        expect(count_8k).to eq(0)
      end

      it "does not return the API total when block is given" do
        count_all = collection.count { |_f| true }
        expect(count_all).to eq(3) # Current page size, not 5000
      end

      it "counts filings matching specific ticker" do
        count_aapl = collection.count { |f| f.ticker == "AAPL" }
        expect(count_aapl).to eq(1)
      end
    end
  end

  describe "immutability" do
    let(:filings_data) do
      {
        filings: [
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
        ],
        total: 1
      }
    end

    let(:collection) { described_class.new(filings_data) }

    it "freezes the internal array of filings" do
      expect(collection.filings).to be_frozen
    end

    it "does not allow modification of filings array" do
      expect { collection.filings << "new item" }.to raise_error(FrozenError)
    end
  end

  describe "pagination metadata" do
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

    context "when more pages exist (API format with from and total)" do
      let(:filings_data) do
        {
          filings: Array.new(50) { |i| filing_template.merge(accessionNo: "000119312524#{format("%06d", i)}") },
          from: "0",
          total: {value: 100, relation: "eq"}
        }
      end

      let(:mock_client) { instance_double("SecApi::Client") }
      let(:collection) { described_class.new(filings_data, client: mock_client, query_context: {}) }

      it "exposes next_cursor as calculated offset" do
        expect(collection.next_cursor).to eq(50)
      end

      it "returns true for #has_more? when client is present" do
        expect(collection.has_more?).to be true
      end

      it "exposes total_count" do
        expect(collection.total_count).to eq({value: 100, relation: "eq"})
      end
    end

    context "when on last page (next_cursor >= total)" do
      let(:filings_data) do
        {
          filings: Array.new(10) { |i| filing_template.merge(accessionNo: "000119312524#{format("%06d", i)}") },
          from: "90",
          total: {value: 100, relation: "eq"}
        }
      end

      let(:mock_client) { instance_double("SecApi::Client") }
      let(:collection) { described_class.new(filings_data, client: mock_client, query_context: {}) }

      it "returns next_cursor at total boundary" do
        expect(collection.next_cursor).to eq(100)
      end

      it "returns false for #has_more?" do
        expect(collection.has_more?).to be false
      end
    end

    context "when no client present (backward compatibility)" do
      let(:filings_data) do
        {
          filings: Array.new(50) { |i| filing_template.merge(accessionNo: "000119312524#{format("%06d", i)}") },
          from: "0",
          total: 100
        }
      end

      let(:collection) { described_class.new(filings_data) }

      it "calculates next_cursor" do
        expect(collection.next_cursor).to eq(50)
      end

      it "returns false for #has_more? without client" do
        expect(collection.has_more?).to be false
      end
    end
  end

  describe "thread safety" do
    let(:filings_data) do
      {
        filings: [
          {
            id: "1",
            accessionNo: "0001193125-24-001234",
            ticker: "AAPL",
            cik: "0000320193",
            formType: "10-K",
            filedAt: "2024-01-15",
            companyName: "Apple Inc",
            companyNameLong: "Apple Inc.",
            period_of_report: "2023-12-31",
            linkToTxt: "https://example.com",
            linkToHtml: "https://example.com",
            linkToXbrl: "https://example.com",
            linkToFilingDetails: "https://example.com",
            entities: [],
            documentFormatFiles: [],
            dataFiles: []
          }
        ],
        total: 1
      }
    end

    let(:collection) { described_class.new(filings_data) }

    it "allows concurrent iteration from multiple threads" do
      results = []
      mutex = Mutex.new

      threads = 5.times.map do
        Thread.new do
          collection.each do |filing|
            mutex.synchronize { results << filing.ticker }
          end
        end
      end

      threads.each(&:join)
      expect(results).to eq(["AAPL"] * 5)
    end
  end

  describe "parsing API response" do
    let(:filings_data) do
      {
        filings: [
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
        ],
        total: 1
      }
    end

    let(:collection) { described_class.new(filings_data) }

    it "parses filings array into Filing objects" do
      expect(collection.filings.first).to be_a(SecApi::Objects::Filing)
      expect(collection.filings.first.ticker).to eq("AAPL")
    end

    it "handles empty filings array" do
      empty_collection = described_class.new({filings: [], total: 0})
      expect(empty_collection.filings).to be_empty
      expect(empty_collection.count).to eq(0)
    end
  end

  describe "#fetch_next_page" do
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

    let(:stubs) { Faraday::Adapter::Test::Stubs.new }
    let(:connection) do
      Faraday.new do |builder|
        builder.request :json
        builder.response :json, parser_options: {symbolize_names: true}
        builder.adapter :test, stubs
      end
    end
    let(:mock_client) do
      client = instance_double("SecApi::Client")
      allow(client).to receive(:connection).and_return(connection)
      client
    end

    let(:query_context) do
      {query: "ticker:AAPL", size: "50", sort: [{"filedAt" => {"order" => "desc"}}]}
    end

    after { stubs.verify_stubbed_calls }

    context "when more pages exist" do
      let(:first_page_data) do
        {
          filings: [filing_template.merge(accessionNo: "0001193125-24-000001")],
          total: {value: 100, relation: "eq"},
          from: "0"
        }
      end

      let(:second_page_data) do
        {
          filings: [filing_template.merge(accessionNo: "0001193125-24-000002")],
          total: {value: 100, relation: "eq"},
          from: "1"
        }
      end

      let(:collection) do
        described_class.new(first_page_data, client: mock_client, query_context: query_context)
      end

      it "makes API request with next offset" do
        stubs.post("/") do |env|
          body = JSON.parse(env.body)
          expect(body["from"]).to eq("1")
          [200, {"Content-Type" => "application/json"}, second_page_data.to_json]
        end

        collection.fetch_next_page
      end

      it "returns a new Filings collection" do
        stubs.post("/") { [200, {"Content-Type" => "application/json"}, second_page_data.to_json] }

        result = collection.fetch_next_page
        expect(result).to be_a(described_class)
        expect(result).not_to be(collection)
      end

      it "preserves original collection (immutable)" do
        stubs.post("/") { [200, {"Content-Type" => "application/json"}, second_page_data.to_json] }

        original_accession = collection.first.accession_number
        collection.fetch_next_page
        expect(collection.first.accession_number).to eq(original_accession)
      end

      it "returns a collection that can continue paginating" do
        stubs.post("/") { [200, {"Content-Type" => "application/json"}, second_page_data.to_json] }

        result = collection.fetch_next_page
        expect(result.has_more?).to be true
      end
    end

    context "when no more pages exist" do
      let(:last_page_data) do
        {
          filings: [filing_template],
          total: {value: 1, relation: "eq"},
          from: "0"
        }
      end

      let(:collection) do
        described_class.new(last_page_data, client: mock_client, query_context: query_context)
      end

      it "raises PaginationError" do
        expect { collection.fetch_next_page }.to raise_error(
          SecApi::PaginationError,
          "No more pages available"
        )
      end
    end

    context "when collection has no client reference" do
      let(:data) do
        {
          filings: [filing_template],
          total: {value: 100, relation: "eq"},
          from: "0"
        }
      end

      let(:collection) { described_class.new(data) }

      it "raises PaginationError because pagination is not possible" do
        expect { collection.fetch_next_page }.to raise_error(
          SecApi::PaginationError,
          "No more pages available"
        )
      end

      it "returns false for has_more? without client" do
        expect(collection.has_more?).to be false
      end
    end
  end

  describe "#has_more? (API-based calculation)" do
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

    let(:mock_client) { instance_double("SecApi::Client") }
    let(:query_context) { {query: "ticker:AAPL"} }

    context "when next_cursor < total" do
      let(:data) do
        {
          filings: Array.new(50) { |i| filing_template.merge(accessionNo: "000119312524#{format("%06d", i)}") },
          total: {value: 100, relation: "eq"},
          from: "0"
        }
      end

      let(:collection) { described_class.new(data, client: mock_client, query_context: query_context) }

      it "returns true" do
        expect(collection.has_more?).to be true
      end

      it "calculates next_cursor as from + page_size" do
        expect(collection.next_cursor).to eq(50)
      end
    end

    context "when on last page (next_cursor >= total)" do
      let(:data) do
        {
          filings: Array.new(25) { |i| filing_template.merge(accessionNo: "000119312524#{format("%06d", i)}") },
          total: {value: 75, relation: "eq"},
          from: "50"
        }
      end

      let(:collection) { described_class.new(data, client: mock_client, query_context: query_context) }

      it "returns false" do
        expect(collection.has_more?).to be false
      end

      it "calculates next_cursor as from + page_size" do
        expect(collection.next_cursor).to eq(75)
      end
    end

    context "when total is an integer (not object)" do
      let(:data) do
        {
          filings: Array.new(10) { |i| filing_template.merge(accessionNo: "000119312524#{format("%06d", i)}") },
          total: 50,
          from: "0"
        }
      end

      let(:collection) { described_class.new(data, client: mock_client, query_context: query_context) }

      it "returns true when more pages exist" do
        expect(collection.has_more?).to be true
      end
    end
  end

  describe "#next_cursor (offset-based)" do
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

    it "calculates next_cursor from API from field + page size" do
      data = {
        filings: Array.new(50) { |i| filing_template.merge(accessionNo: "000119312524#{format("%06d", i)}") },
        total: {value: 200, relation: "eq"},
        from: "100"
      }
      collection = described_class.new(data)
      expect(collection.next_cursor).to eq(150)
    end

    it "defaults from to 0 when not present" do
      data = {
        filings: Array.new(10) { |i| filing_template.merge(accessionNo: "000119312524#{format("%06d", i)}") },
        total: 100
      }
      collection = described_class.new(data)
      expect(collection.next_cursor).to eq(10)
    end
  end

  describe "#auto_paginate" do
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

    let(:stubs) { Faraday::Adapter::Test::Stubs.new }
    let(:connection) do
      Faraday.new do |builder|
        builder.request :json
        builder.response :json, parser_options: {symbolize_names: true}
        builder.adapter :test, stubs
      end
    end
    let(:mock_client) do
      client = instance_double("SecApi::Client")
      allow(client).to receive(:connection).and_return(connection)
      client
    end
    let(:query_context) do
      {query: "ticker:AAPL", size: "50", sort: [{"filedAt" => {"order" => "desc"}}]}
    end

    after { stubs.verify_stubbed_calls }

    context "with multiple pages" do
      let(:page1_data) do
        {
          filings: Array.new(3) { |i| filing_template.merge(accessionNo: "0001193125-24-00000#{i}") },
          total: {value: 5, relation: "eq"},
          from: "0"
        }
      end

      let(:page2_data) do
        {
          filings: Array.new(2) { |i| filing_template.merge(accessionNo: "0001193125-24-00000#{i + 3}") },
          total: {value: 5, relation: "eq"},
          from: "3"
        }
      end

      let(:collection) do
        described_class.new(page1_data, client: mock_client, query_context: query_context)
      end

      it "returns an Enumerator::Lazy" do
        expect(collection.auto_paginate).to be_a(Enumerator::Lazy)
      end

      it "yields Filing objects (not collections)" do
        collection.auto_paginate.first.tap do |filing|
          expect(filing).to be_a(SecApi::Objects::Filing)
        end
      end

      it "transparently fetches next page at page boundary" do
        stubs.post("/") { [200, {"Content-Type" => "application/json"}, page2_data.to_json] }
        all_filings = collection.auto_paginate.to_a
        expect(all_filings.size).to eq(5)
      end

      it "collects all filings with to_a across pages" do
        stubs.post("/") { [200, {"Content-Type" => "application/json"}, page2_data.to_json] }
        all_accession_numbers = collection.auto_paginate.map(&:accession_number).to_a
        expect(all_accession_numbers).to eq([
          "0001193125-24-000000",
          "0001193125-24-000001",
          "0001193125-24-000002",
          "0001193125-24-000003",
          "0001193125-24-000004"
        ])
      end

      it "stops when has_more? returns false" do
        stubs.post("/") { [200, {"Content-Type" => "application/json"}, page2_data.to_json] }
        count = 0
        collection.auto_paginate.each { count += 1 }
        expect(count).to eq(5)
      end
    end

    context "without client reference" do
      let(:data) do
        {
          filings: [filing_template],
          total: {value: 100, relation: "eq"},
          from: "0"
        }
      end

      let(:collection) { described_class.new(data) }

      it "raises PaginationError" do
        expect { collection.auto_paginate }.to raise_error(
          SecApi::PaginationError,
          "Cannot paginate without client reference"
        )
      end
    end

    context "with single page result" do
      let(:data) do
        {
          filings: Array.new(10) { |i| filing_template.merge(accessionNo: "0001193125-24-00000#{i}") },
          total: {value: 10, relation: "eq"},
          from: "0"
        }
      end

      let(:collection) do
        described_class.new(data, client: mock_client, query_context: query_context)
      end

      it "yields all filings without additional fetch" do
        all_filings = collection.auto_paginate.to_a
        expect(all_filings.size).to eq(10)
        # No stubs needed - no additional API calls should be made
      end
    end

    context "with empty result set" do
      let(:data) do
        {
          filings: [],
          total: {value: 0, relation: "eq"},
          from: "0"
        }
      end

      let(:collection) do
        described_class.new(data, client: mock_client, query_context: query_context)
      end

      it "yields nothing" do
        expect(collection.auto_paginate.to_a).to be_empty
      end
    end

    context "defensive guard against API misbehavior" do
      # Scenario: API returns empty page mid-pagination but claims more exist
      # This could cause infinite loop without defensive guard
      let(:page1_data) do
        {
          filings: Array.new(3) { |i| filing_template.merge(accessionNo: "0001193125-24-00000#{i}") },
          total: {value: 100, relation: "eq"}, # Claims 100 total
          from: "0"
        }
      end

      let(:empty_page_data) do
        {
          filings: [], # Empty - API misbehavior
          total: {value: 100, relation: "eq"}, # Still claims 100 total
          from: "3" # Same offset as calculated next_cursor
        }
      end

      let(:collection) do
        described_class.new(page1_data, client: mock_client, query_context: query_context)
      end

      it "breaks loop when API returns empty page with same cursor (infinite loop guard)" do
        stubs.post("/") { [200, {"Content-Type" => "application/json"}, empty_page_data.to_json] }

        # Should NOT infinite loop - should return only page 1 filings
        all_filings = collection.auto_paginate.to_a
        expect(all_filings.size).to eq(3) # Only page 1
      end
    end

    context "lazy evaluation" do
      let(:page1_data) do
        {
          filings: Array.new(50) { |i| filing_template.merge(accessionNo: "0001193125-24-#{format("%06d", i)}") },
          total: {value: 200, relation: "eq"},
          from: "0"
        }
      end

      let(:collection) do
        described_class.new(page1_data, client: mock_client, query_context: query_context)
      end

      it "does not fetch next page until needed" do
        # Take only from first page - should NOT trigger page 2 fetch
        first_10 = collection.auto_paginate.take(10).to_a
        expect(first_10.size).to eq(10)
        # stubs.verify_stubbed_calls would fail if we had stubbed a second page
        # Since we didn't stub anything, this verifies no API call was made
      end
    end

    context "retry behavior (Task 3)" do
      let(:retry_stubs) { Faraday::Adapter::Test::Stubs.new }
      let(:retry_connection) do
        Faraday.new do |builder|
          builder.request :json
          builder.response :json, parser_options: {symbolize_names: true}
          # Add retry middleware to test transient error recovery
          builder.request :retry, {
            max: 2,
            interval: 0.01,
            retry_statuses: [503],
            methods: [:post]
          }
          builder.adapter :test, retry_stubs
        end
      end
      let(:retry_mock_client) do
        client = instance_double("SecApi::Client")
        allow(client).to receive(:connection).and_return(retry_connection)
        client
      end

      let(:page1_data) do
        {
          filings: Array.new(3) { |i| filing_template.merge(accessionNo: "0001193125-24-00000#{i}") },
          total: {value: 5, relation: "eq"},
          from: "0"
        }
      end

      let(:page2_data) do
        {
          filings: Array.new(2) { |i| filing_template.merge(accessionNo: "0001193125-24-00000#{i + 3}") },
          total: {value: 5, relation: "eq"},
          from: "3"
        }
      end

      let(:collection) do
        described_class.new(page1_data, client: retry_mock_client, query_context: query_context)
      end

      it "retries transient errors (503) during pagination and continues" do
        # Page 2 fails with 503 on first attempt, then succeeds on retry
        call_count = 0
        retry_stubs.post("/") do |_env|
          call_count += 1
          if call_count == 1
            [503, {}, "Service Unavailable"]
          else
            [200, {"Content-Type" => "application/json"}, page2_data.to_json]
          end
        end

        all_filings = collection.auto_paginate.to_a

        expect(all_filings.size).to eq(5)
        expect(call_count).to eq(2) # First failed, second succeeded
      end

      it "pagination continues through fetch_next_page which uses client connection" do
        # This verifies that auto_paginate uses fetch_next_page which goes through
        # the client's connection, where retry middleware is applied
        retry_stubs.post("/") { [200, {"Content-Type" => "application/json"}, page2_data.to_json] }

        all_filings = collection.auto_paginate.to_a
        expect(all_filings.size).to eq(5)
      end
    end
  end
end
