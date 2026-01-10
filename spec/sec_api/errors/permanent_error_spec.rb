# frozen_string_literal: true

require "spec_helper"

RSpec.describe SecApi::PermanentError do
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
      error = described_class.new("Test permanent error")
      expect(error.message).to eq("Test permanent error")
    end

    it "can be instantiated without a message" do
      error = described_class.new
      expect(error).to be_a(described_class)
    end
  end

  describe "rescue behavior" do
    it "can be rescued as SecApi::PermanentError" do
      expect {
        begin
          raise described_class, "Test error"
        rescue SecApi::PermanentError => e
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
    it "represents non-retryable errors" do
      # This is a semantic test - PermanentError indicates non-retry-eligible errors
      error = described_class.new("Configuration issue")
      expect(error).to be_a(SecApi::PermanentError)
    end
  end

  describe "request_id propagation" do
    it "accepts request_id keyword argument" do
      error = described_class.new("Permanent error", request_id: "perm-123")
      expect(error.request_id).to eq("perm-123")
    end

    it "includes request_id in error message" do
      error = described_class.new("Permanent error", request_id: "perm-456")
      expect(error.message).to eq("[perm-456] Permanent error")
    end

    it "passes request_id to parent Error class" do
      error = described_class.new("Test", request_id: "req-789")
      expect(error).to be_a(SecApi::Error)
      expect(error.request_id).to eq("req-789")
    end
  end
end
