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
    context "when next_cursor is present" do
      let(:filings_data) do
        {
          filings: [],
          next_cursor: "cursor_abc123",
          total: 100
        }
      end

      let(:collection) { described_class.new(filings_data) }

      it "exposes next_cursor" do
        expect(collection.next_cursor).to eq("cursor_abc123")
      end

      it "returns true for #has_more?" do
        expect(collection.has_more?).to be true
      end

      it "exposes total_count" do
        expect(collection.total_count).to eq(100)
      end
    end

    context "when next_cursor is nil (last page)" do
      let(:filings_data) do
        {
          filings: [],
          next_cursor: nil,
          total: 10
        }
      end

      let(:collection) { described_class.new(filings_data) }

      it "returns nil for next_cursor" do
        expect(collection.next_cursor).to be_nil
      end

      it "returns false for #has_more?" do
        expect(collection.has_more?).to be false
      end
    end

    context "when next_cursor is missing (single page)" do
      let(:filings_data) do
        {
          filings: [],
          total: 5
        }
      end

      let(:collection) { described_class.new(filings_data) }

      it "returns nil for next_cursor" do
        expect(collection.next_cursor).to be_nil
      end

      it "returns false for #has_more?" do
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
end
