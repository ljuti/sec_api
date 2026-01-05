# frozen_string_literal: true

require "spec_helper"

RSpec.describe SecApi::TransientError do
  describe "inheritance" do
    it "inherits from SecApi::Error" do
      expect(described_class).to be < SecApi::Error
    end

    it "includes SecApi::Error in ancestry chain" do
      expect(described_class.ancestors).to include(SecApi::Error)
    end

    it "includes StandardError in ancestry chain" do
      expect(described_class.ancestors).to include(StandardError)
    end
  end

  describe "instantiation" do
    it "can be instantiated with a custom message" do
      error = described_class.new("Test transient error")
      expect(error.message).to eq("Test transient error")
    end

    it "can be instantiated without a message" do
      error = described_class.new
      expect(error).to be_a(described_class)
    end
  end

  describe "rescue behavior" do
    it "can be rescued as SecApi::TransientError" do
      expect {
        begin
          raise described_class, "Test error"
        rescue SecApi::TransientError => e
          expect(e.message).to eq("Test error")
        end
      }.not_to raise_error
    end

    it "can be rescued as SecApi::Error" do
      expect {
        begin
          raise described_class, "Test error"
        rescue SecApi::Error => e
          expect(e.message).to eq("Test error")
        end
      }.not_to raise_error
    end

    it "can be rescued as StandardError" do
      expect {
        begin
          raise described_class, "Test error"
        rescue => e
          expect(e.message).to eq("Test error")
        end
      }.not_to raise_error
    end
  end

  describe "semantic meaning" do
    it "represents retryable errors" do
      # This is a semantic test - TransientError indicates retry-eligible errors
      error = described_class.new("Temporary failure")
      expect(error).to be_a(SecApi::TransientError)
    end
  end
end
