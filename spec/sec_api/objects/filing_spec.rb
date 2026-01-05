require "spec_helper"

RSpec.describe SecApi::Objects::Filing do
  describe "Dry::Struct inheritance" do
    it "inherits from Dry::Struct" do
      expect(described_class.ancestors).to include(Dry::Struct)
    end
  end

  describe "immutability" do
    let(:filing) do
      described_class.new(
        id: "123",
        accession_number: "0001193125-24-001234",
        ticker: "AAPL",
        cik: "0000320193",
        form_type: "10-K",
        filed_at: "2024-01-15",
        company_name: "Apple Inc",
        company_name_long: "Apple Inc.",
        period_of_report: "2023-12-31",
        txt_url: "https://example.com/filing.txt",
        html_url: "https://example.com/filing.html",
        xbrl_url: "https://example.com/filing.xbrl",
        filing_details_url: "https://example.com/details",
        entities: [],
        documents: [],
        data_files: []
      )
    end

    it "is frozen (immutable)" do
      expect(filing).to be_frozen
    end

    it "does not allow attribute modification" do
      expect { filing.accession_number = "new" }.to raise_error(NoMethodError, /undefined method/)
    end

    it "does not provide setter methods" do
      expect(filing).not_to respond_to(:accession_number=)
      expect(filing).not_to respond_to(:ticker=)
    end
  end

  describe "type coercion" do
    context "when filed_at is a Date string" do
      let(:filing) do
        described_class.new(
          id: "123",
          accession_number: "0001193125-24-001234",
          ticker: "AAPL",
          cik: "0000320193",
          form_type: "10-K",
          filed_at: "2024-01-15",
          company_name: "Apple Inc",
          company_name_long: "Apple Inc.",
          period_of_report: "2023-12-31",
          txt_url: "https://example.com",
          html_url: "https://example.com",
          xbrl_url: "https://example.com",
          filing_details_url: "https://example.com",
          entities: [],
          documents: [],
          data_files: []
        )
      end

      it "coerces string to Date object" do
        expect(filing.filed_at).to be_a(Date)
        expect(filing.filed_at.year).to eq(2024)
        expect(filing.filed_at.month).to eq(1)
        expect(filing.filed_at.day).to eq(15)
      end
    end
  end

  describe "required attributes" do
    it "requires accession_number" do
      expect do
        described_class.new(
          id: "123",
          ticker: "AAPL",
          cik: "0000320193",
          form_type: "10-K",
          filed_at: "2024-01-15",
          company_name: "Apple Inc",
          company_name_long: "Apple Inc.",
          period_of_report: "2023-12-31",
          txt_url: "https://example.com",
          html_url: "https://example.com",
          xbrl_url: "https://example.com",
          filing_details_url: "https://example.com",
          entities: [],
          documents: [],
          data_files: []
          # accession_number missing
        )
      end.to raise_error(Dry::Struct::Error)
    end
  end

  describe "thread safety" do
    let(:filing) do
      described_class.new(
        id: "123",
        accession_number: "0001193125-24-001234",
        ticker: "AAPL",
        cik: "0000320193",
        form_type: "10-K",
        filed_at: "2024-01-15",
        company_name: "Apple Inc",
        company_name_long: "Apple Inc.",
        period_of_report: "2023-12-31",
        txt_url: "https://example.com",
        html_url: "https://example.com",
        xbrl_url: "https://example.com",
        filing_details_url: "https://example.com",
        entities: [],
        documents: [],
        data_files: []
      )
    end

    it "allows concurrent access from multiple threads without errors" do
      threads = 10.times.map do
        Thread.new do
          100.times do
            filing.accession_number
            filing.ticker
            filing.form_type
          end
        end
      end

      expect { threads.each(&:join) }.not_to raise_error
    end

    it "returns consistent values across threads" do
      results = []
      mutex = Mutex.new

      threads = 5.times.map do
        Thread.new do
          mutex.synchronize { results << filing.ticker }
        end
      end

      threads.each(&:join)
      expect(results.uniq).to eq(["AAPL"])
    end
  end

  describe "#url helper method" do
    context "when html_url is present" do
      let(:filing) do
        described_class.new(
          id: "123",
          accession_number: "0001193125-24-001234",
          ticker: "AAPL",
          cik: "0000320193",
          form_type: "10-K",
          filed_at: "2024-01-15",
          company_name: "Apple Inc",
          company_name_long: "Apple Inc.",
          period_of_report: "2023-12-31",
          txt_url: "https://example.com/txt",
          html_url: "https://example.com/html",
          xbrl_url: "https://example.com/xbrl",
          filing_details_url: "https://example.com/details",
          entities: [],
          documents: [],
          data_files: []
        )
      end

      it "returns html_url" do
        expect(filing.url).to eq("https://example.com/html")
      end
    end

    context "when html_url is blank but txt_url is present" do
      let(:filing) do
        described_class.new(
          id: "123",
          accession_number: "0001193125-24-001234",
          ticker: "AAPL",
          cik: "0000320193",
          form_type: "10-K",
          filed_at: "2024-01-15",
          company_name: "Apple Inc",
          company_name_long: "Apple Inc.",
          period_of_report: "2023-12-31",
          txt_url: "https://example.com/txt",
          html_url: "",
          xbrl_url: "https://example.com/xbrl",
          filing_details_url: "https://example.com/details",
          entities: [],
          documents: [],
          data_files: []
        )
      end

      it "returns txt_url" do
        expect(filing.url).to eq("https://example.com/txt")
      end
    end
  end
end
