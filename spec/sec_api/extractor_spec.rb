# frozen_string_literal: true

require "spec_helper"

RSpec.describe SecApi::Extractor do
  let(:config) { SecApi::Config.new(api_key: "test_api_key_valid") }
  let(:client) { SecApi::Client.new(config) }
  let(:extractor) { client.extractor }

  describe "#extract" do
    it "returns ExtractedData object (not raw hash)" do
      stubs = Faraday::Adapter::Test::Stubs.new
      stubs.post("/extractor") do
        [200, {"Content-Type" => "application/json"}, {
          "text" => "Sample extracted text from filing",
          "sections" => {
            "risk_factors" => "Risk factors content",
            "financials" => "Financial statements content"
          },
          "metadata" => {
            "source_url" => "https://www.sec.gov/Archives/edgar/data/320193/000032019324000123/example.htm",
            "form_type" => "10-K"
          }
        }.to_json]
      end

      allow(client).to receive(:connection).and_return(
        Faraday.new do |conn|
          conn.request :json
          conn.response :json, content_type: /\bjson$/, parser_options: {symbolize_names: true}
          conn.use SecApi::Middleware::ErrorHandler
          conn.adapter :test, stubs
        end
      )

      extracted = extractor.extract("https://www.sec.gov/Archives/edgar/data/320193/000032019324000123/example.htm")

      expect(extracted).to be_a(SecApi::ExtractedData)
      expect(extracted).not_to be_a(Hash)
      stubs.verify_stubbed_calls
    end

    it "provides access to attributes via methods (not hash keys)" do
      stubs = Faraday::Adapter::Test::Stubs.new
      stubs.post("/extractor") do
        [200, {"Content-Type" => "application/json"}, {
          "text" => "Extracted filing text",
          "sections" => {
            "risk_factors" => "Risk content"
          }
        }.to_json]
      end

      allow(client).to receive(:connection).and_return(
        Faraday.new do |conn|
          conn.request :json
          conn.response :json, content_type: /\bjson$/, parser_options: {symbolize_names: true}
          conn.use SecApi::Middleware::ErrorHandler
          conn.adapter :test, stubs
        end
      )

      extracted = extractor.extract("https://example.com/filing.htm")

      expect(extracted.text).to eq("Extracted filing text")
      expect(extracted.sections).to eq({risk_factors: "Risk content"})
      stubs.verify_stubbed_calls
    end

    it "is immutable (frozen)" do
      stubs = Faraday::Adapter::Test::Stubs.new
      stubs.post("/extractor") do
        [200, {"Content-Type" => "application/json"}, {
          "text" => "Sample text"
        }.to_json]
      end

      allow(client).to receive(:connection).and_return(
        Faraday.new do |conn|
          conn.request :json
          conn.response :json, content_type: /\bjson$/, parser_options: {symbolize_names: true}
          conn.use SecApi::Middleware::ErrorHandler
          conn.adapter :test, stubs
        end
      )

      extracted = extractor.extract("https://example.com/filing.htm")

      expect(extracted).to be_frozen
      stubs.verify_stubbed_calls
    end

    it "handles Filing object input" do
      filing = double("Filing", url: "https://www.sec.gov/filing.htm")

      stubs = Faraday::Adapter::Test::Stubs.new
      stubs.post("/extractor") do
        [200, {"Content-Type" => "application/json"}, {
          "text" => "Extracted from filing object"
        }.to_json]
      end

      allow(client).to receive(:connection).and_return(
        Faraday.new do |conn|
          conn.request :json
          conn.response :json, content_type: /\bjson$/, parser_options: {symbolize_names: true}
          conn.use SecApi::Middleware::ErrorHandler
          conn.adapter :test, stubs
        end
      )

      extracted = extractor.extract(filing)

      expect(extracted).to be_a(SecApi::ExtractedData)
      expect(extracted.text).to eq("Extracted from filing object")
      stubs.verify_stubbed_calls
    end
  end
end
