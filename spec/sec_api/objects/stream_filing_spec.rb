# frozen_string_literal: true

require "spec_helper"

RSpec.describe SecApi::Objects::StreamFiling do
  let(:valid_attributes) do
    {
      accession_no: "0001193125-24-123456",
      form_type: "8-K",
      filed_at: "2024-01-15T16:30:00-05:00",
      cik: "320193",
      ticker: "AAPL",
      company_name: "Apple Inc.",
      link_to_filing_details: "https://sec-api.io/filing/0001193125-24-123456",
      link_to_txt: "https://www.sec.gov/Archives/...",
      link_to_html: "https://www.sec.gov/Archives/...",
      period_of_report: "2024-01-15"
    }
  end

  describe ".new" do
    it "creates a StreamFiling with valid attributes" do
      filing = described_class.new(valid_attributes)

      expect(filing.accession_no).to eq("0001193125-24-123456")
      expect(filing.form_type).to eq("8-K")
      expect(filing.filed_at).to eq("2024-01-15T16:30:00-05:00")
      expect(filing.cik).to eq("320193")
      expect(filing.ticker).to eq("AAPL")
      expect(filing.company_name).to eq("Apple Inc.")
      expect(filing.link_to_filing_details).to eq("https://sec-api.io/filing/0001193125-24-123456")
    end

    it "handles optional fields as nil" do
      minimal_attributes = {
        accession_no: "0001-24-001",
        form_type: "8-K",
        filed_at: "2024-01-15T16:30:00-05:00",
        cik: "123",
        company_name: "Test Corp",
        link_to_filing_details: "https://sec-api.io/..."
      }

      filing = described_class.new(minimal_attributes)

      expect(filing.ticker).to be_nil
      expect(filing.link_to_txt).to be_nil
      expect(filing.link_to_html).to be_nil
      expect(filing.period_of_report).to be_nil
      expect(filing.entities).to be_nil
      expect(filing.document_format_files).to be_nil
      expect(filing.data_files).to be_nil
    end

    it "raises error for missing required fields" do
      expect {
        described_class.new(accession_no: "123")
      }.to raise_error(Dry::Struct::Error)
    end
  end

  describe "immutability" do
    it "freezes the instance after creation" do
      filing = described_class.new(valid_attributes)
      expect(filing).to be_frozen
    end

    it "prevents modification of attributes" do
      filing = described_class.new(valid_attributes)

      expect { filing.instance_variable_set(:@form_type, "10-K") }.to raise_error(FrozenError)
    end
  end

  describe "nested array handling" do
    let(:attributes_with_entities) do
      valid_attributes.merge(
        entities: [
          {"cik" => "320193", "companyName" => "Apple Inc."},
          {"cik" => "999999", "companyName" => "Related Entity"}
        ]
      )
    end

    it "accepts entities array" do
      filing = described_class.new(attributes_with_entities)
      expect(filing.entities).to be_an(Array)
      expect(filing.entities.size).to eq(2)
    end

    it "freezes nested entities array" do
      filing = described_class.new(attributes_with_entities)
      expect(filing.entities).to be_frozen
    end

    it "freezes nested entity hashes" do
      filing = described_class.new(attributes_with_entities)
      expect(filing.entities.first).to be_frozen
    end
  end

  describe "document format files handling" do
    let(:attributes_with_documents) do
      valid_attributes.merge(
        document_format_files: [
          {"sequence" => "1", "description" => "Complete submission text file", "documentUrl" => "https://..."},
          {"sequence" => "2", "description" => "8-K form", "documentUrl" => "https://..."}
        ]
      )
    end

    it "accepts document_format_files array" do
      filing = described_class.new(attributes_with_documents)
      expect(filing.document_format_files).to be_an(Array)
      expect(filing.document_format_files.size).to eq(2)
    end

    it "freezes document_format_files" do
      filing = described_class.new(attributes_with_documents)
      expect(filing.document_format_files).to be_frozen
    end
  end

  describe "data files handling" do
    let(:attributes_with_data_files) do
      valid_attributes.merge(
        data_files: [
          {"sequence" => "1", "description" => "XBRL Instance", "documentUrl" => "https://..."}
        ]
      )
    end

    it "accepts data_files array" do
      filing = described_class.new(attributes_with_data_files)
      expect(filing.data_files).to be_an(Array)
      expect(filing.data_files.size).to eq(1)
    end

    it "freezes data_files" do
      filing = described_class.new(attributes_with_data_files)
      expect(filing.data_files).to be_frozen
    end
  end

  describe "form types" do
    %w[10-K 10-Q 8-K 20-F 40-F 6-K DEF 14A S-1 4].each do |form|
      it "accepts form_type #{form}" do
        attrs = valid_attributes.merge(form_type: form)
        filing = described_class.new(attrs)
        expect(filing.form_type).to eq(form)
      end
    end
  end

  describe "ticker handling" do
    it "accepts nil ticker for filers without stock listing" do
      attrs = valid_attributes.merge(ticker: nil)
      filing = described_class.new(attrs)
      expect(filing.ticker).to be_nil
    end

    it "accepts empty string ticker" do
      # Some API responses may have empty string
      attrs = valid_attributes.merge(ticker: "")
      filing = described_class.new(attrs)
      expect(filing.ticker).to eq("")
    end
  end

  describe "convenience methods (Story 6.3)" do
    describe "#url" do
      it "returns link_to_html when available" do
        filing = described_class.new(valid_attributes)
        expect(filing.url).to eq(valid_attributes[:link_to_html])
      end

      it "returns link_to_txt when link_to_html is nil" do
        attrs = valid_attributes.merge(link_to_html: nil)
        filing = described_class.new(attrs)
        expect(filing.url).to eq(valid_attributes[:link_to_txt])
      end

      it "returns link_to_txt when link_to_html is empty string" do
        attrs = valid_attributes.merge(link_to_html: "")
        filing = described_class.new(attrs)
        expect(filing.url).to eq(valid_attributes[:link_to_txt])
      end

      it "returns nil when both links are nil" do
        attrs = valid_attributes.merge(link_to_html: nil, link_to_txt: nil)
        filing = described_class.new(attrs)
        expect(filing.url).to be_nil
      end

      it "returns nil when both links are empty strings" do
        attrs = valid_attributes.merge(link_to_html: "", link_to_txt: "")
        filing = described_class.new(attrs)
        expect(filing.url).to be_nil
      end
    end

    describe "#filing_url" do
      it "is an alias for #url" do
        filing = described_class.new(valid_attributes)
        expect(filing.filing_url).to eq(filing.url)
      end
    end

    describe "#accession_number" do
      it "is an alias for #accession_no" do
        filing = described_class.new(valid_attributes)
        expect(filing.accession_number).to eq(filing.accession_no)
      end
    end

    describe "#html_url" do
      it "is an alias for #link_to_html" do
        filing = described_class.new(valid_attributes)
        expect(filing.html_url).to eq(filing.link_to_html)
      end
    end

    describe "#txt_url" do
      it "is an alias for #link_to_txt" do
        filing = described_class.new(valid_attributes)
        expect(filing.txt_url).to eq(filing.link_to_txt)
      end
    end
  end
end
