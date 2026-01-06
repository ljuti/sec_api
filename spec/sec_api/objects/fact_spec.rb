# frozen_string_literal: true

require "spec_helper"

RSpec.describe SecApi::Fact do
  describe "attributes" do
    it "accepts value as required string" do
      fact = described_class.new(value: "394328000000")
      expect(fact.value).to eq("394328000000")
    end

    it "accepts decimals as optional string" do
      fact = described_class.new(value: "1000", decimals: "-6")
      expect(fact.decimals).to eq("-6")
    end

    it "accepts unit_ref as optional string" do
      fact = described_class.new(value: "1000", unit_ref: "usd")
      expect(fact.unit_ref).to eq("usd")
    end

    it "accepts segment as optional hash" do
      segment = {dimension: "ProductLine", value: "iPhone"}
      fact = described_class.new(value: "1000", segment: segment)
      expect(fact.segment).to eq(segment)
    end

    it "allows nil for optional attributes" do
      fact = described_class.new(value: "1000")
      expect(fact.decimals).to be_nil
      expect(fact.unit_ref).to be_nil
      expect(fact.segment).to be_nil
      expect(fact.period).to be_nil
    end
  end

  describe "period attribute" do
    it "accepts period with start_date and end_date (duration)" do
      period = SecApi::Period.new(
        start_date: Date.new(2022, 9, 25),
        end_date: Date.new(2023, 9, 30)
      )
      fact = described_class.new(value: "1000", period: period)

      expect(fact.period.start_date).to eq(Date.new(2022, 9, 25))
      expect(fact.period.end_date).to eq(Date.new(2023, 9, 30))
    end

    it "accepts period with instant (point-in-time)" do
      period = SecApi::Period.new(instant: Date.new(2023, 9, 30))
      fact = described_class.new(value: "1000", period: period)

      expect(fact.period.instant).to eq(Date.new(2023, 9, 30))
    end
  end

  describe "#to_numeric" do
    it "converts string value to float" do
      fact = described_class.new(value: "394328000000")
      expect(fact.to_numeric).to eq(394328000000.0)
    end

    it "handles decimal values" do
      fact = described_class.new(value: "123.45")
      expect(fact.to_numeric).to eq(123.45)
    end

    it "handles negative values" do
      fact = described_class.new(value: "-50000")
      expect(fact.to_numeric).to eq(-50000.0)
    end

    it "returns 0.0 for non-numeric strings" do
      fact = described_class.new(value: "N/A")
      expect(fact.to_numeric).to eq(0.0)
    end
  end

  describe "#numeric?" do
    it "returns true for positive integers" do
      fact = described_class.new(value: "394328000000")
      expect(fact.numeric?).to be true
    end

    it "returns true for negative integers" do
      fact = described_class.new(value: "-50000")
      expect(fact.numeric?).to be true
    end

    it "returns true for decimal values" do
      fact = described_class.new(value: "123.45")
      expect(fact.numeric?).to be true
    end

    it "returns true for negative decimal values" do
      fact = described_class.new(value: "-123.45")
      expect(fact.numeric?).to be true
    end

    it "returns true for zero" do
      fact = described_class.new(value: "0")
      expect(fact.numeric?).to be true
    end

    it "returns true for scientific notation" do
      fact = described_class.new(value: "1.5e10")
      expect(fact.numeric?).to be true
    end

    it "returns true for negative scientific notation" do
      fact = described_class.new(value: "-2.5E-3")
      expect(fact.numeric?).to be true
    end

    it "returns false for text values" do
      fact = described_class.new(value: "N/A")
      expect(fact.numeric?).to be false
    end

    it "returns false for empty string" do
      fact = described_class.new(value: "")
      expect(fact.numeric?).to be false
    end

    it "returns false for strings with commas" do
      fact = described_class.new(value: "1,000,000")
      expect(fact.numeric?).to be false
    end

    it "returns false for currency symbols" do
      fact = described_class.new(value: "$100")
      expect(fact.numeric?).to be false
    end

    it "returns false for mixed alphanumeric" do
      fact = described_class.new(value: "100 million")
      expect(fact.numeric?).to be false
    end

    it "returns false for percentage format" do
      fact = described_class.new(value: "10%")
      expect(fact.numeric?).to be false
    end

    it "returns true for leading/trailing whitespace around valid numbers" do
      fact = described_class.new(value: "  123.45  ")
      expect(fact.numeric?).to be true
    end

    it "returns false for whitespace-only string" do
      fact = described_class.new(value: "   ")
      expect(fact.numeric?).to be false
    end

    it "returns false for leading plus sign (XBRL uses unadorned positive numbers)" do
      fact = described_class.new(value: "+123")
      expect(fact.numeric?).to be false
    end
  end

  describe "immutability" do
    it "is frozen after creation" do
      fact = described_class.new(value: "1000", decimals: "-6", unit_ref: "usd")
      expect(fact).to be_frozen
    end

    it "has frozen segment hash" do
      segment = {dimension: "ProductLine", value: "iPhone"}
      fact = described_class.new(value: "1000", segment: segment)
      expect(fact.segment).to be_frozen
    end

    it "has frozen period" do
      period = SecApi::Period.new(instant: Date.new(2023, 9, 30))
      fact = described_class.new(value: "1000", period: period)
      expect(fact.period).to be_frozen
    end
  end

  describe ".from_api" do
    it "parses API response with camelCase keys" do
      api_data = {
        "value" => "394328000000",
        "decimals" => "-6",
        "unitRef" => "usd",
        "period" => {
          "startDate" => "2022-09-25",
          "endDate" => "2023-09-30"
        },
        "segment" => nil
      }

      fact = described_class.from_api(api_data)

      expect(fact.value).to eq("394328000000")
      expect(fact.decimals).to eq("-6")
      expect(fact.unit_ref).to eq("usd")
      expect(fact.period.start_date).to eq(Date.new(2022, 9, 25))
      expect(fact.period.end_date).to eq(Date.new(2023, 9, 30))
    end

    it "parses API response with instant period" do
      api_data = {
        "value" => "352755000000",
        "decimals" => "-6",
        "unitRef" => "usd",
        "period" => {
          "instant" => "2023-09-30"
        }
      }

      fact = described_class.from_api(api_data)

      expect(fact.period.instant).to eq(Date.new(2023, 9, 30))
      expect(fact.period.start_date).to be_nil
      expect(fact.period.end_date).to be_nil
    end

    it "handles symbol keys from parsed JSON" do
      api_data = {
        value: "1000",
        decimals: "-3",
        unitRef: "usd",
        period: {startDate: "2023-01-01", endDate: "2023-12-31"}
      }

      fact = described_class.from_api(api_data)

      expect(fact.value).to eq("1000")
      expect(fact.unit_ref).to eq("usd")
    end

    it "handles missing optional fields" do
      api_data = {"value" => "1000"}

      fact = described_class.from_api(api_data)

      expect(fact.value).to eq("1000")
      expect(fact.decimals).to be_nil
      expect(fact.unit_ref).to be_nil
      expect(fact.period).to be_nil
    end

    it "raises ValidationError when value is nil" do
      api_data = {"decimals" => "-6", "unitRef" => "usd"}

      expect {
        described_class.from_api(api_data)
      }.to raise_error(SecApi::ValidationError, /missing required 'value' field/)
    end

    it "raises ValidationError when value key is missing entirely" do
      api_data = {}

      expect {
        described_class.from_api(api_data)
      }.to raise_error(SecApi::ValidationError, /missing required 'value' field/)
    end
  end
end

RSpec.describe SecApi::Period do
  describe "attributes" do
    it "accepts start_date and end_date for duration periods" do
      period = described_class.new(
        start_date: Date.new(2022, 9, 25),
        end_date: Date.new(2023, 9, 30)
      )

      expect(period.start_date).to eq(Date.new(2022, 9, 25))
      expect(period.end_date).to eq(Date.new(2023, 9, 30))
      expect(period.instant).to be_nil
    end

    it "accepts instant for point-in-time periods" do
      period = described_class.new(instant: Date.new(2023, 9, 30))

      expect(period.instant).to eq(Date.new(2023, 9, 30))
      expect(period.start_date).to be_nil
      expect(period.end_date).to be_nil
    end

    it "coerces ISO 8601 date strings" do
      period = described_class.new(
        start_date: "2022-09-25",
        end_date: "2023-09-30"
      )

      expect(period.start_date).to eq(Date.new(2022, 9, 25))
      expect(period.end_date).to eq(Date.new(2023, 9, 30))
    end
  end

  describe "#duration?" do
    it "returns true for duration periods" do
      period = described_class.new(
        start_date: Date.new(2022, 9, 25),
        end_date: Date.new(2023, 9, 30)
      )
      expect(period.duration?).to be true
    end

    it "returns false for instant periods" do
      period = described_class.new(instant: Date.new(2023, 9, 30))
      expect(period.duration?).to be false
    end
  end

  describe "#instant?" do
    it "returns true for instant periods" do
      period = described_class.new(instant: Date.new(2023, 9, 30))
      expect(period.instant?).to be true
    end

    it "returns false for duration periods" do
      period = described_class.new(
        start_date: Date.new(2022, 9, 25),
        end_date: Date.new(2023, 9, 30)
      )
      expect(period.instant?).to be false
    end
  end

  describe "immutability" do
    it "is frozen after creation" do
      period = described_class.new(instant: Date.new(2023, 9, 30))
      expect(period).to be_frozen
    end
  end

  describe ".from_api" do
    it "parses duration period from API" do
      api_data = {
        "startDate" => "2022-09-25",
        "endDate" => "2023-09-30"
      }

      period = described_class.from_api(api_data)

      expect(period.start_date).to eq(Date.new(2022, 9, 25))
      expect(period.end_date).to eq(Date.new(2023, 9, 30))
    end

    it "parses instant period from API" do
      api_data = {"instant" => "2023-09-30"}

      period = described_class.from_api(api_data)

      expect(period.instant).to eq(Date.new(2023, 9, 30))
    end

    it "handles symbol keys" do
      api_data = {startDate: "2023-01-01", endDate: "2023-12-31"}

      period = described_class.from_api(api_data)

      expect(period.start_date).to eq(Date.new(2023, 1, 1))
      expect(period.end_date).to eq(Date.new(2023, 12, 31))
    end
  end
end
