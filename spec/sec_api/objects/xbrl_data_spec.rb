# frozen_string_literal: true

require "spec_helper"

RSpec.describe SecApi::XbrlData do
  describe "structure and inheritance" do
    it "inherits from Dry::Struct" do
      expect(described_class).to be < Dry::Struct
    end

    it "creates instance with valid attributes" do
      xbrl_data = described_class.new(
        financials: {revenue: 1_000_000.0, assets: 5_000_000.0}
      )

      expect(xbrl_data).to be_a(SecApi::XbrlData)
      expect(xbrl_data.financials[:revenue]).to eq(1_000_000.0)
      expect(xbrl_data.financials[:assets]).to eq(5_000_000.0)
    end
  end

  describe "immutability" do
    let(:xbrl_data) do
      described_class.new(
        financials: {revenue: 1_000_000.0, assets: 5_000_000.0},
        metadata: {source_url: "https://example.com"}
      )
    end

    it "is frozen after initialization" do
      expect(xbrl_data).to be_frozen
    end

    it "has frozen nested financials hash" do
      expect(xbrl_data.financials).to be_frozen
    end

    it "has frozen nested metadata hash" do
      expect(xbrl_data.metadata).to be_frozen
    end

    it "raises error when trying to modify financials" do
      expect {
        xbrl_data.financials[:revenue] = 9_999_999.0
      }.to raise_error(FrozenError)
    end
  end

  describe "type coercion" do
    it "coerces string revenue to float" do
      xbrl_data = described_class.new(
        financials: {revenue: "1000000.50"}
      )

      expect(xbrl_data.financials[:revenue]).to eq(1_000_000.5)
      expect(xbrl_data.financials[:revenue]).to be_a(Float)
    end

    it "coerces string assets to float" do
      xbrl_data = described_class.new(
        financials: {assets: "5000000.75"}
      )

      expect(xbrl_data.financials[:assets]).to eq(5_000_000.75)
      expect(xbrl_data.financials[:assets]).to be_a(Float)
    end
  end

  describe "optional attributes" do
    it "accepts nil financials" do
      xbrl_data = described_class.new(financials: nil)
      expect(xbrl_data.financials).to be_nil
    end

    it "accepts nil metadata" do
      xbrl_data = described_class.new(metadata: nil)
      expect(xbrl_data.metadata).to be_nil
    end

    it "accepts nil validation_results" do
      xbrl_data = described_class.new(validation_results: nil)
      expect(xbrl_data.validation_results).to be_nil
    end

    it "accepts financials with nil revenue" do
      xbrl_data = described_class.new(
        financials: {revenue: nil, assets: 5_000_000.0}
      )

      expect(xbrl_data.financials[:revenue]).to be_nil
      expect(xbrl_data.financials[:assets]).to eq(5_000_000.0)
    end
  end

  describe "schema flexibility for XBRL taxonomy variations" do
    it "ignores unknown top-level attributes" do
      # XBRL APIs may return unexpected fields - we should not fail
      xbrl_data = described_class.new(
        financials: {revenue: 1000.0},
        unknown_field: "ignored"
      )

      expect(xbrl_data.financials[:revenue]).to eq(1000.0)
      expect(xbrl_data).not_to respond_to(:unknown_field)
    end

    it "allows unknown financial metrics for taxonomy flexibility" do
      # Different XBRL taxonomies use different field names
      xbrl_data = described_class.new(
        financials: {revenue: 1000.0, custom_metric: 999.0}
      )

      expect(xbrl_data.financials[:revenue]).to eq(1000.0)
      # Unknown fields are silently ignored in optional schemas
    end

    it "allows unknown metadata fields" do
      # Future API versions may add new metadata fields
      xbrl_data = described_class.new(
        metadata: {source_url: "https://example.com", future_field: "allowed"}
      )

      expect(xbrl_data.metadata[:source_url]).to eq("https://example.com")
    end
  end

  describe "thread safety" do
    it "is thread-safe for concurrent reads" do
      xbrl_data = described_class.new(
        financials: {
          revenue: 1_000_000.0,
          assets: 5_000_000.0,
          liabilities: 2_000_000.0,
          equity: 3_000_000.0
        }
      )

      # Spawn 10 threads accessing the same object
      threads = 10.times.map do
        Thread.new do
          100.times do
            xbrl_data.financials[:revenue]
            xbrl_data.financials[:assets]
            xbrl_data.financials[:liabilities]
            xbrl_data.financials[:equity]
          end
        end
      end

      # All threads complete without errors
      expect { threads.each(&:join) }.not_to raise_error
    end

    it "maintains data integrity across concurrent access" do
      xbrl_data = described_class.new(
        financials: {revenue: 1_000_000.0}
      )

      results = []
      threads = 10.times.map do
        Thread.new do
          xbrl_data.financials[:revenue]
        end
      end

      threads.each { |t| results << t.value }

      # All threads read the same value
      expect(results.uniq).to eq([1_000_000.0])
    end

    it "prevents concurrent modification attempts" do
      xbrl_data = described_class.new(
        financials: {revenue: 1_000_000.0, assets: 5_000_000.0}
      )

      # Spawn 10 threads all trying to modify the frozen financials hash
      threads = 10.times.map do
        Thread.new do
          expect {
            xbrl_data.financials[:revenue] = 9_999_999.0
          }.to raise_error(FrozenError)
        end
      end

      # All threads complete with expected FrozenError
      expect { threads.each(&:join) }.not_to raise_error
    end
  end

  describe "nested schema structure" do
    it "accepts all financial metrics when provided" do
      xbrl_data = described_class.new(
        financials: {
          revenue: 1_000_000.0,
          total_revenue: 1_100_000.0,
          assets: 5_000_000.0,
          total_assets: 5_500_000.0,
          current_assets: 2_000_000.0,
          liabilities: 2_000_000.0,
          total_liabilities: 2_200_000.0,
          current_liabilities: 800_000.0,
          stockholders_equity: 3_000_000.0,
          equity: 3_000_000.0,
          cash_flow: 500_000.0,
          operating_cash_flow: 550_000.0,
          period_end_date: Date.new(2024, 12, 31)
        }
      )

      expect(xbrl_data.financials[:revenue]).to eq(1_000_000.0)
      expect(xbrl_data.financials[:total_revenue]).to eq(1_100_000.0)
      expect(xbrl_data.financials[:assets]).to eq(5_000_000.0)
      expect(xbrl_data.financials[:period_end_date]).to eq(Date.new(2024, 12, 31))
    end

    it "accepts metadata with all fields" do
      xbrl_data = described_class.new(
        metadata: {
          source_url: "https://www.sec.gov/example",
          retrieved_at: DateTime.new(2025, 1, 5, 12, 0, 0),
          form_type: "10-K",
          cik: "0000320193",
          ticker: "AAPL"
        }
      )

      expect(xbrl_data.metadata[:source_url]).to eq("https://www.sec.gov/example")
      expect(xbrl_data.metadata[:form_type]).to eq("10-K")
      expect(xbrl_data.metadata[:ticker]).to eq("AAPL")
    end

    it "accepts validation_results with passed and errors" do
      xbrl_data = described_class.new(
        validation_results: {
          passed: false,
          errors: ["Missing revenue field", "Invalid date format"],
          warnings: ["Deprecated field used"]
        }
      )

      expect(xbrl_data.validation_results[:passed]).to eq(false)
      expect(xbrl_data.validation_results[:errors]).to eq(["Missing revenue field", "Invalid date format"])
      expect(xbrl_data.validation_results[:warnings]).to eq(["Deprecated field used"])
    end
  end
end
