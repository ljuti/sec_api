require "spec_helper"

RSpec.describe SecApi::Error do
  describe "base error class" do
    it "inherits from StandardError" do
      expect(SecApi::Error.new).to be_a(StandardError)
    end

    it "accepts a message" do
      error = SecApi::Error.new("test message")
      expect(error.message).to eq("test message")
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
