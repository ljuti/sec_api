# frozen_string_literal: true

require "spec_helper"

RSpec.describe SecApi::RateLimitState do
  describe "attributes" do
    it "creates with all attributes" do
      reset_time = Time.now + 60
      state = described_class.new(
        limit: 100,
        remaining: 95,
        reset_at: reset_time
      )

      expect(state.limit).to eq(100)
      expect(state.remaining).to eq(95)
      expect(state.reset_at).to eq(reset_time)
    end

    it "creates with no attributes (unknown state)" do
      state = described_class.new

      expect(state.limit).to be_nil
      expect(state.remaining).to be_nil
      expect(state.reset_at).to be_nil
    end

    it "creates with partial attributes" do
      state = described_class.new(remaining: 50)

      expect(state.limit).to be_nil
      expect(state.remaining).to eq(50)
      expect(state.reset_at).to be_nil
    end

    it "coerces string values to integers" do
      state = described_class.new(
        limit: "100",
        remaining: "95"
      )

      expect(state.limit).to eq(100)
      expect(state.remaining).to eq(95)
    end

    it "accepts symbol keys" do
      state = described_class.new(limit: 100, remaining: 95)
      expect(state.limit).to eq(100)
    end

    it "accepts string keys" do
      state = described_class.new("limit" => 100, "remaining" => 95)
      expect(state.limit).to eq(100)
    end
  end

  describe "#exhausted?" do
    it "returns true when remaining is zero" do
      state = described_class.new(limit: 100, remaining: 0)
      expect(state.exhausted?).to be true
    end

    it "returns false when remaining is greater than zero" do
      state = described_class.new(limit: 100, remaining: 5)
      expect(state.exhausted?).to be false
    end

    it "returns false when remaining is unknown (nil)" do
      state = described_class.new(limit: 100)
      expect(state.exhausted?).to be false
    end

    it "returns false for completely unknown state" do
      state = described_class.new
      expect(state.exhausted?).to be false
    end
  end

  describe "#available?" do
    it "returns true when remaining is greater than zero" do
      state = described_class.new(limit: 100, remaining: 5)
      expect(state.available?).to be true
    end

    it "returns true when remaining is unknown (nil)" do
      state = described_class.new(limit: 100)
      expect(state.available?).to be true
    end

    it "returns true for completely unknown state" do
      state = described_class.new
      expect(state.available?).to be true
    end

    it "returns false when remaining is zero" do
      state = described_class.new(limit: 100, remaining: 0)
      expect(state.available?).to be false
    end
  end

  describe "#percentage_remaining" do
    it "calculates percentage correctly" do
      state = described_class.new(limit: 100, remaining: 25)
      expect(state.percentage_remaining).to eq(25.0)
    end

    it "returns 0.0 when remaining is zero" do
      state = described_class.new(limit: 100, remaining: 0)
      expect(state.percentage_remaining).to eq(0.0)
    end

    it "returns 100.0 when at full quota" do
      state = described_class.new(limit: 100, remaining: 100)
      expect(state.percentage_remaining).to eq(100.0)
    end

    it "returns nil when limit is unknown" do
      state = described_class.new(remaining: 50)
      expect(state.percentage_remaining).to be_nil
    end

    it "returns nil when remaining is unknown" do
      state = described_class.new(limit: 100)
      expect(state.percentage_remaining).to be_nil
    end

    it "returns nil for completely unknown state" do
      state = described_class.new
      expect(state.percentage_remaining).to be_nil
    end

    it "handles limit of zero gracefully" do
      state = described_class.new(limit: 0, remaining: 0)
      expect(state.percentage_remaining).to eq(0.0)
    end

    it "rounds to one decimal place" do
      state = described_class.new(limit: 3, remaining: 1)
      expect(state.percentage_remaining).to eq(33.3)
    end
  end

  describe "immutability" do
    it "is frozen after creation" do
      state = described_class.new(limit: 100, remaining: 95)
      expect(state).to be_frozen
    end
  end
end
