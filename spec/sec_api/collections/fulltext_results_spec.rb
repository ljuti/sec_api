# frozen_string_literal: true

require "spec_helper"

RSpec.describe SecApi::Collections::FulltextResults do
  describe "Enumerable interface" do
    let(:fulltext_data) do
      {
        filings: [
          {
            id: "1",
            accessionNo: "0001193125-24-001234",
            ticker: "AAPL",
            cik: "0000320193",
            formType: "8-K",
            filedAt: "2024-01-15",
            companyName: "Apple Inc",
            companyNameLong: "Apple Inc.",
            description: "Acquisition announcement merger",
            type: "8-K",
            url: "https://example.com/1",
            linkToTxt: "https://example.com/1.txt",
            linkToHtml: "https://example.com/1.html",
            linkToFilingDetails: "https://example.com/1",
            filedOn: "2024-01-15"
          },
          {
            id: "2",
            accessionNo: "0001193125-24-001235",
            ticker: "MSFT",
            cik: "0000789019",
            formType: "10-K",
            filedAt: "2024-01-16",
            companyName: "Microsoft Corp",
            companyNameLong: "Microsoft Corporation",
            description: "Annual report with merger details",
            type: "10-K",
            url: "https://example.com/2",
            linkToTxt: "https://example.com/2.txt",
            linkToHtml: "https://example.com/2.html",
            linkToFilingDetails: "https://example.com/2",
            filedOn: "2024-01-16"
          }
        ]
      }
    end

    let(:collection) { described_class.new(fulltext_data) }

    it "includes Enumerable module" do
      expect(described_class.ancestors).to include(Enumerable)
    end

    it "implements #each" do
      expect(collection).to respond_to(:each)
    end

    it "yields FulltextResult objects in each iteration" do
      collection.each do |result|
        expect(result).to be_a(SecApi::Objects::FulltextResult)
      end
    end

    it "supports Enumerable methods like #map" do
      tickers = collection.map(&:ticker)
      expect(tickers).to eq(["AAPL", "MSFT"])
    end

    it "supports Enumerable methods like #select" do
      eight_ks = collection.select { |r| r.form_type == "8-K" }
      expect(eight_ks.length).to eq(1)
      expect(eight_ks.first.ticker).to eq("AAPL")
    end

    it "supports Enumerable methods like #count" do
      expect(collection.count).to eq(2)
    end

    it "supports Enumerable methods like #first" do
      first_result = collection.first
      expect(first_result).to be_a(SecApi::Objects::FulltextResult)
      expect(first_result.ticker).to eq("AAPL")
    end
  end

  describe "immutability" do
    let(:fulltext_data) do
      {
        filings: [
          {
            id: "1",
            accessionNo: "0001193125-24-001234",
            ticker: "AAPL",
            cik: "0000320193",
            formType: "8-K",
            filedAt: "2024-01-15",
            companyName: "Apple Inc",
            companyNameLong: "Apple Inc.",
            description: "Acquisition announcement",
            type: "8-K",
            url: "https://example.com",
            filedOn: "2024-01-15",
            linkToTxt: "https://example.com",
            linkToHtml: "https://example.com",
            linkToFilingDetails: "https://example.com"
          }
        ]
      }
    end

    let(:collection) { described_class.new(fulltext_data) }

    it "freezes the internal array of objects" do
      expect(collection.objects).to be_frozen
    end

    it "does not allow modification of objects array" do
      expect { collection.objects << "new item" }.to raise_error(FrozenError)
    end
  end

  describe "backward compatibility accessor" do
    let(:fulltext_data) do
      {
        filings: [
          {
            id: "1",
            accessionNo: "0001193125-24-001234",
            ticker: "AAPL",
            cik: "0000320193",
            formType: "8-K",
            filedAt: "2024-01-15",
            companyName: "Apple Inc",
            companyNameLong: "Apple Inc.",
            description: "Acquisition",
            type: "8-K",
            url: "https://example.com",
            filedOn: "2024-01-15",
            linkToTxt: "https://example.com",
            linkToHtml: "https://example.com",
            linkToFilingDetails: "https://example.com"
          }
        ]
      }
    end

    let(:collection) { described_class.new(fulltext_data) }

    it "provides #fulltext_results accessor for backward compatibility" do
      expect(collection).to respond_to(:fulltext_results)
      expect(collection.fulltext_results).to be_a(Array)
      expect(collection.fulltext_results.first).to be_a(SecApi::Objects::FulltextResult)
    end

    it "#fulltext_results returns the same array as #objects" do
      expect(collection.fulltext_results).to eq(collection.objects)
    end
  end

  describe "thread safety" do
    let(:fulltext_data) do
      {
        filings: [
          {
            id: "1",
            accessionNo: "0001193125-24-001234",
            ticker: "AAPL",
            cik: "0000320193",
            formType: "8-K",
            filedAt: "2024-01-15",
            companyName: "Apple Inc",
            companyNameLong: "Apple Inc.",
            description: "Merger announcement",
            type: "8-K",
            url: "https://example.com",
            filedOn: "2024-01-15",
            linkToTxt: "https://example.com",
            linkToHtml: "https://example.com",
            linkToFilingDetails: "https://example.com"
          }
        ]
      }
    end

    let(:collection) { described_class.new(fulltext_data) }

    it "allows concurrent iteration from multiple threads" do
      results = []
      mutex = Mutex.new

      threads = 5.times.map do
        Thread.new do
          collection.each do |result|
            mutex.synchronize { results << result.ticker }
          end
        end
      end

      threads.each(&:join)
      expect(results).to eq(["AAPL"] * 5)
    end
  end

  describe "parsing API response" do
    let(:fulltext_data) do
      {
        filings: [
          {
            id: "1",
            accessionNo: "0001193125-24-001234",
            ticker: "AAPL",
            cik: "0000320193",
            formType: "8-K",
            filedAt: "2024-01-15",
            companyName: "Apple Inc",
            companyNameLong: "Apple Inc.",
            description: "Merger and acquisition details",
            type: "8-K",
            url: "https://example.com",
            filedOn: "2024-01-15",
            linkToTxt: "https://example.com",
            linkToHtml: "https://example.com",
            linkToFilingDetails: "https://example.com"
          }
        ]
      }
    end

    let(:collection) { described_class.new(fulltext_data) }

    it "parses filings array into FulltextResult objects" do
      expect(collection.fulltext_results.first).to be_a(SecApi::Objects::FulltextResult)
      expect(collection.fulltext_results.first.ticker).to eq("AAPL")
    end

    it "handles empty filings array" do
      empty_collection = described_class.new({filings: []})
      expect(empty_collection.fulltext_results).to be_empty
      expect(empty_collection.count).to eq(0)
    end

    it "parses description field from fulltext search results" do
      expect(collection.first.description).to eq("Merger and acquisition details")
    end
  end
end
