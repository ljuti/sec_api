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

  describe "request_id propagation" do
    it "accepts request_id keyword argument" do
      error = described_class.new("Transient error", request_id: "trans-123")
      expect(error.request_id).to eq("trans-123")
    end

    it "includes request_id in error message" do
      error = described_class.new("Transient error", request_id: "trans-456")
      expect(error.message).to eq("[trans-456] Transient error")
    end

    it "passes request_id to parent Error class" do
      error = described_class.new("Test", request_id: "req-789")
      expect(error).to be_a(SecApi::Error)
      expect(error.request_id).to eq("req-789")
    end
  end
end
