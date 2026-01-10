require "spec_helper"

RSpec.describe SecApi::Error do
  describe "base error class" do
    it "inherits from StandardError" do
      expect(SecApi::Error.new("error")).to be_a(StandardError)
    end

    it "accepts a message" do
      error = SecApi::Error.new("test message")
      expect(error.message).to eq("test message")
    end
  end

  describe "request_id attribute" do
    it "accepts request_id keyword argument" do
      error = SecApi::Error.new("test message", request_id: "abc-123")
      expect(error.request_id).to eq("abc-123")
    end

    it "includes request_id in error message when provided" do
      error = SecApi::Error.new("Something failed", request_id: "req-456")
      expect(error.message).to eq("[req-456] Something failed")
    end

    it "does not prefix message when request_id is nil" do
      error = SecApi::Error.new("Something failed", request_id: nil)
      expect(error.message).to eq("Something failed")
    end

    it "does not prefix message when request_id is not provided" do
      error = SecApi::Error.new("Something failed")
      expect(error.message).to eq("Something failed")
      expect(error.request_id).to be_nil
    end

    it "handles empty string request_id" do
      error = SecApi::Error.new("Something failed", request_id: "")
      # Empty string is falsy in the context of our check
      expect(error.message).to eq("Something failed")
    end

    it "preserves full UUID request_id format" do
      uuid = "550e8400-e29b-41d4-a716-446655440000"
      error = SecApi::Error.new("API error", request_id: uuid)
      expect(error.message).to eq("[#{uuid}] API error")
      expect(error.request_id).to eq(uuid)
    end
  end
end

RSpec.describe SecApi::ConfigurationError do
  describe "error inheritance" do
    it "inherits from SecApi::Error" do
      expect(SecApi::ConfigurationError.new).to be_a(SecApi::Error)
    end

    it "inherits from StandardError through SecApi::Error" do
      expect(SecApi::ConfigurationError.new).to be_a(StandardError)
    end
  end

  describe "error message" do
    it "accepts a custom message" do
      error = SecApi::ConfigurationError.new("api_key is required")
      expect(error.message).to eq("api_key is required")
    end
  end
end
