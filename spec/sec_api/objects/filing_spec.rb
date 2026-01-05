require "spec_helper"

RSpec.describe SecApi::Objects::Filing do
  describe "Dry::Struct inheritance" do
    it "inherits from Dry::Struct" do
      expect(described_class.ancestors).to include(Dry::Struct)
    end
  end

  describe "attribute accessors (AC #1)" do
    let(:filing) do
      described_class.new(
        id: "abc123",
        accession_number: "0000320193-24-000001",
        ticker: "AAPL",
        cik: "320193",
        form_type: "10-K",
        filed_at: "2024-01-15",
        company_name: "Apple Inc",
        company_name_long: "Apple Inc.",
        period_of_report: "2023-12-31",
        txt_url: "https://sec.gov/filing.txt",
        html_url: "https://sec.gov/filing.html",
        xbrl_url: "https://sec.gov/filing.xbrl",
        filing_details_url: "https://sec.gov/details",
        entities: [],
        documents: [],
        data_files: []
      )
    end

    it "exposes ticker" do
      expect(filing.ticker).to eq("AAPL")
    end

    it "exposes cik" do
      expect(filing.cik).to eq("320193")
    end

    it "exposes form_type" do
      expect(filing.form_type).to eq("10-K")
    end

    it "exposes company_name" do
      expect(filing.company_name).to eq("Apple Inc")
    end

    it "exposes accession_number" do
      expect(filing.accession_number).to eq("0000320193-24-000001")
    end

    it "exposes filed_at as Date object" do
      expect(filing.filed_at).to be_a(Date)
      expect(filing.filed_at).to eq(Date.new(2024, 1, 15))
    end

    it "exposes filing URL via #url helper" do
      expect(filing.url).to eq("https://sec.gov/filing.html")
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

      it "is NOT a String (AC #2 explicit verification)" do
        expect(filing.filed_at).not_to be_a(String)
      end

      it "handles ISO 8601 datetime strings from API" do
        filing_with_datetime = described_class.new(
          id: "123",
          accession_number: "0001193125-24-001234",
          ticker: "AAPL",
          cik: "0000320193",
          form_type: "10-K",
          filed_at: "2024-01-15T16:30:00-05:00",
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
        expect(filing_with_datetime.filed_at).to be_a(Date)
        expect(filing_with_datetime.filed_at).to eq(Date.new(2024, 1, 15))
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

  describe "#accession_no alias" do
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

    it "returns the accession number" do
      expect(filing.accession_no).to eq("0001193125-24-001234")
    end

    it "is an alias for #accession_number" do
      expect(filing.accession_no).to eq(filing.accession_number)
    end
  end

  describe "#filing_url alias" do
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

    it "returns the filing URL" do
      expect(filing.filing_url).to eq("https://example.com/filing.html")
    end

    it "is an alias for #url" do
      expect(filing.filing_url).to eq(filing.url)
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
