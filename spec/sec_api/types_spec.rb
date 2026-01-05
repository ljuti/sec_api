require "spec_helper"

RSpec.describe SecApi::Types do
  describe "module inclusion" do
    it "includes Dry.Types()" do
      expect(described_class.constants).to include(:String)
    end
  end

  describe "String type" do
    it "accepts string values" do
      expect(SecApi::Types::String["test"]).to eq("test")
    end

    it "rejects non-string values" do
      expect { SecApi::Types::String[123] }.to raise_error(Dry::Types::ConstraintError)
    end
  end

  describe "Coercible::String type" do
    it "coerces various types to string" do
      expect(SecApi::Types::Coercible::String[123]).to eq("123")
      expect(SecApi::Types::Coercible::String[:symbol]).to eq("symbol")
    end
  end

  describe "JSON::Date type" do
    it "coerces ISO 8601 string to Date object" do
      date = SecApi::Types::JSON::Date["2024-01-15"]
      expect(date).to be_a(Date)
      expect(date.year).to eq(2024)
      expect(date.month).to eq(1)
      expect(date.day).to eq(15)
    end

    it "handles Date objects directly" do
      date_obj = Date.new(2024, 1, 15)
      expect(SecApi::Types::JSON::Date[date_obj]).to eq(date_obj)
    end
  end

  describe "JSON::DateTime type" do
    it "coerces ISO 8601 string to DateTime object" do
      datetime = SecApi::Types::JSON::DateTime["2024-01-15T10:30:00Z"]
      expect(datetime).to be_a(DateTime)
      expect(datetime.year).to eq(2024)
    end
  end

  describe "Coercible::Integer type" do
    it "coerces string to integer" do
      expect(SecApi::Types::Coercible::Integer["123"]).to eq(123)
    end

    it "handles integer directly" do
      expect(SecApi::Types::Coercible::Integer[456]).to eq(456)
    end
  end

  describe "Coercible::Float type" do
    it "coerces string to float" do
      expect(SecApi::Types::Coercible::Float["123.45"]).to eq(123.45)
    end

    it "coerces integer to float" do
      expect(SecApi::Types::Coercible::Float[123]).to eq(123.0)
    end
  end

  describe "optional types" do
    it "allows nil values" do
      optional_string = SecApi::Types::String.optional
      expect(optional_string[nil]).to be_nil
      expect(optional_string["test"]).to eq("test")
    end
  end
end
