# frozen_string_literal: true

require "spec_helper"

RSpec.describe SecApi::Objects::Entity do
  describe "Dry::Struct inheritance" do
    it "inherits from Dry::Struct" do
      expect(described_class.ancestors).to include(Dry::Struct)
    end
  end

  describe "attribute definitions" do
    let(:entity) do
      described_class.new(
        cik: "0000320193",
        name: "Apple Inc.",
        ticker: "AAPL",
        exchange: "NASDAQ",
        irs_number: "94-2404110",
        state_of_incorporation: "CA",
        fiscal_year_end: "0930",
        type: "10-K",
        act: "34",
        file_number: "001-36743",
        film_number: "24123456",
        sic: "3571",
        cusip: "037833100"
      )
    end

    it "exposes cik as required String" do
      expect(entity.cik).to eq("0000320193")
    end

    it "preserves CIK leading zeros" do
      expect(entity.cik).to start_with("0000")
      expect(entity.cik.length).to eq(10)
    end

    it "exposes optional attributes via methods" do
      expect(entity.name).to eq("Apple Inc.")
      expect(entity.ticker).to eq("AAPL")
      expect(entity.exchange).to eq("NASDAQ")
      expect(entity.irs_number).to eq("94-2404110")
      expect(entity.state_of_incorporation).to eq("CA")
      expect(entity.fiscal_year_end).to eq("0930")
      expect(entity.type).to eq("10-K")
      expect(entity.act).to eq("34")
      expect(entity.file_number).to eq("001-36743")
      expect(entity.film_number).to eq("24123456")
      expect(entity.sic).to eq("3571")
      expect(entity.cusip).to eq("037833100")
    end

    it "allows nil for optional attributes" do
      minimal_entity = described_class.new(cik: "0000320193")

      expect(minimal_entity.cik).to eq("0000320193")
      expect(minimal_entity.name).to be_nil
      expect(minimal_entity.ticker).to be_nil
      expect(minimal_entity.exchange).to be_nil
      expect(minimal_entity.cusip).to be_nil
    end

    it "requires cik attribute" do
      expect {
        described_class.new(name: "Apple Inc.")
      }.to raise_error(Dry::Struct::Error)
    end
  end

  describe "immutability" do
    let(:entity) { described_class.new(cik: "0000320193", name: "Apple Inc.") }

    it "is frozen after construction" do
      expect(entity).to be_frozen
    end

    it "prevents attribute modification" do
      expect {
        entity.instance_variable_set(:@cik, "changed")
      }.to raise_error(FrozenError)
    end
  end

  describe ".from_api" do
    context "with symbol keys (parsed JSON with symbolize_names)" do
      it "creates Entity from symbolized response" do
        data = {
          cik: "0000320193",
          ticker: "AAPL",
          companyName: "Apple Inc.",
          exchange: "NASDAQ"
        }

        entity = described_class.from_api(data)

        expect(entity.cik).to eq("0000320193")
        expect(entity.ticker).to eq("AAPL")
        expect(entity.name).to eq("Apple Inc.")
        expect(entity.exchange).to eq("NASDAQ")
      end

      it "extracts cusip from API response" do
        data = {
          cik: "0000320193",
          ticker: "AAPL",
          cusip: "037833100"
        }

        entity = described_class.from_api(data)

        expect(entity.cusip).to eq("037833100")
      end

      it "normalizes camelCase API fields to snake_case" do
        data = {
          cik: "0000320193",
          companyName: "Apple Inc.",
          irsNo: "94-2404110",
          stateOfIncorporation: "CA",
          fiscalYearEnd: "0930",
          fileNo: "001-36743",
          filmNo: "24123456"
        }

        entity = described_class.from_api(data)

        expect(entity.name).to eq("Apple Inc.")
        expect(entity.irs_number).to eq("94-2404110")
        expect(entity.state_of_incorporation).to eq("CA")
        expect(entity.fiscal_year_end).to eq("0930")
        expect(entity.file_number).to eq("001-36743")
        expect(entity.film_number).to eq("24123456")
      end
    end

    context "with string keys (raw JSON parse)" do
      it "creates Entity from string-keyed response" do
        data = {
          "cik" => "0000320193",
          "ticker" => "AAPL",
          "companyName" => "Apple Inc."
        }

        entity = described_class.from_api(data)

        expect(entity.cik).to eq("0000320193")
        expect(entity.ticker).to eq("AAPL")
        expect(entity.name).to eq("Apple Inc.")
      end

      it "extracts cusip from string-keyed response" do
        data = {
          "cik" => "0000320193",
          "cusip" => "037833100"
        }

        entity = described_class.from_api(data)

        expect(entity.cusip).to eq("037833100")
      end
    end

    context "with mixed keys (defensive handling)" do
      it "handles mixed symbol and string keys" do
        data = {
          :cik => "0000320193",
          "ticker" => "AAPL",
          :companyName => "Apple Inc.",
          "exchange" => "NASDAQ"
        }

        entity = described_class.from_api(data)

        expect(entity.cik).to eq("0000320193")
        expect(entity.ticker).to eq("AAPL")
        expect(entity.name).to eq("Apple Inc.")
        expect(entity.exchange).to eq("NASDAQ")
      end
    end

    context "with missing optional fields" do
      it "creates Entity with nil for missing fields" do
        data = {cik: "0000320193"}

        entity = described_class.from_api(data)

        expect(entity.cik).to eq("0000320193")
        expect(entity.name).to be_nil
        expect(entity.ticker).to be_nil
        expect(entity.exchange).to be_nil
      end
    end

    context "with already snake_case fields" do
      it "handles pre-normalized snake_case keys" do
        data = {
          cik: "0000320193",
          name: "Apple Inc.",
          irs_number: "94-2404110",
          state_of_incorporation: "CA"
        }

        entity = described_class.from_api(data)

        expect(entity.name).to eq("Apple Inc.")
        expect(entity.irs_number).to eq("94-2404110")
        expect(entity.state_of_incorporation).to eq("CA")
      end
    end

    context "immutability of returned object" do
      it "returns a frozen Entity" do
        data = {cik: "0000320193", ticker: "AAPL"}

        entity = described_class.from_api(data)

        expect(entity).to be_frozen
      end
    end

    context "non-destructive normalization" do
      it "does not mutate the input data" do
        data = {cik: "0000320193", companyName: "Apple Inc."}
        original_data = data.dup

        described_class.from_api(data)

        expect(data).to eq(original_data)
      end
    end
  end
end
