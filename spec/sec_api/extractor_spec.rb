# frozen_string_literal: true

require "spec_helper"

RSpec.describe SecApi::Extractor do
  let(:config) { SecApi::Config.new(api_key: "test_api_key_valid") }
  let(:client) { SecApi::Client.new(config) }
  let(:extractor) { client.extractor }
  let(:filing_url) { "https://www.sec.gov/Archives/edgar/data/320193/000032019324000123/example.htm" }

  describe "#extract" do
    it "returns extracted text as a string" do
      stubs = Faraday::Adapter::Test::Stubs.new
      stubs.get("/extractor") do |env|
        expect(env.params["item"]).to eq("1A")
        expect(env.params["url"]).to eq(filing_url)
        expect(env.params["token"]).to eq("test_api_key_valid")
        [200, {"Content-Type" => "text/plain"}, "Risk factors content from filing"]
      end

      allow(client).to receive(:connection).and_return(
        Faraday.new do |conn|
          conn.use SecApi::Middleware::ErrorHandler
          conn.adapter :test, stubs
        end
      )

      result = extractor.extract(filing_url, item: :risk_factors)

      expect(result).to be_a(String)
      expect(result).to eq("Risk factors content from filing")
      stubs.verify_stubbed_calls
    end

    it "accepts Filing object and extracts URL" do
      filing = double("Filing", url: filing_url)

      stubs = Faraday::Adapter::Test::Stubs.new
      stubs.get("/extractor") do |env|
        expect(env.params["url"]).to eq(filing_url)
        [200, {"Content-Type" => "text/plain"}, "Extracted content"]
      end

      allow(client).to receive(:connection).and_return(
        Faraday.new do |conn|
          conn.use SecApi::Middleware::ErrorHandler
          conn.adapter :test, stubs
        end
      )

      result = extractor.extract(filing, item: :risk_factors)

      expect(result).to eq("Extracted content")
      stubs.verify_stubbed_calls
    end

    it "defaults type to text" do
      stubs = Faraday::Adapter::Test::Stubs.new
      stubs.get("/extractor") do |env|
        expect(env.params["type"]).to eq("text")
        [200, {"Content-Type" => "text/plain"}, "Text content"]
      end

      allow(client).to receive(:connection).and_return(
        Faraday.new do |conn|
          conn.use SecApi::Middleware::ErrorHandler
          conn.adapter :test, stubs
        end
      )

      extractor.extract(filing_url, item: :risk_factors)
      stubs.verify_stubbed_calls
    end

    it "allows html type" do
      stubs = Faraday::Adapter::Test::Stubs.new
      stubs.get("/extractor") do |env|
        expect(env.params["type"]).to eq("html")
        [200, {"Content-Type" => "text/html"}, "<p>HTML content</p>"]
      end

      allow(client).to receive(:connection).and_return(
        Faraday.new do |conn|
          conn.use SecApi::Middleware::ErrorHandler
          conn.adapter :test, stubs
        end
      )

      result = extractor.extract(filing_url, item: :risk_factors, type: "html")

      expect(result).to eq("<p>HTML content</p>")
      stubs.verify_stubbed_calls
    end

    context "section mapping" do
      {
        risk_factors: "1A",
        business: "1",
        mda: "7",
        financials: "8",
        legal_proceedings: "3",
        properties: "2",
        market_risk: "7A"
      }.each do |symbol, expected_item|
        it "maps :#{symbol} to item #{expected_item}" do
          stubs = Faraday::Adapter::Test::Stubs.new
          stubs.get("/extractor") do |env|
            expect(env.params["item"]).to eq(expected_item)
            [200, {"Content-Type" => "text/plain"}, "Content"]
          end

          allow(client).to receive(:connection).and_return(
            Faraday.new do |conn|
              conn.use SecApi::Middleware::ErrorHandler
              conn.adapter :test, stubs
            end
          )

          extractor.extract(filing_url, item: symbol)
          stubs.verify_stubbed_calls
        end
      end

      it "passes through unknown item codes as-is" do
        stubs = Faraday::Adapter::Test::Stubs.new
        stubs.get("/extractor") do |env|
          expect(env.params["item"]).to eq("part2item1a")
          [200, {"Content-Type" => "text/plain"}, "10-Q content"]
        end

        allow(client).to receive(:connection).and_return(
          Faraday.new do |conn|
            conn.use SecApi::Middleware::ErrorHandler
            conn.adapter :test, stubs
          end
        )

        extractor.extract(filing_url, item: "part2item1a")
        stubs.verify_stubbed_calls
      end
    end

    context "error handling" do
      it "raises NotFoundError for 404 response" do
        stubs = Faraday::Adapter::Test::Stubs.new
        stubs.get("/extractor") do
          [404, {"Content-Type" => "application/json"}, '{"error": "Not found"}']
        end

        allow(client).to receive(:connection).and_return(
          Faraday.new do |conn|
            conn.use SecApi::Middleware::ErrorHandler
            conn.adapter :test, stubs
          end
        )

        expect {
          extractor.extract(filing_url, item: :risk_factors)
        }.to raise_error(SecApi::NotFoundError)
      end

      it "raises AuthenticationError for 401 response" do
        stubs = Faraday::Adapter::Test::Stubs.new
        stubs.get("/extractor") do
          [401, {"Content-Type" => "application/json"}, '{"error": "Invalid API key"}']
        end

        allow(client).to receive(:connection).and_return(
          Faraday.new do |conn|
            conn.use SecApi::Middleware::ErrorHandler
            conn.adapter :test, stubs
          end
        )

        expect {
          extractor.extract(filing_url, item: :risk_factors)
        }.to raise_error(SecApi::AuthenticationError)
      end

      it "raises RateLimitError for 429 response" do
        stubs = Faraday::Adapter::Test::Stubs.new
        stubs.get("/extractor") do
          [429, {"Content-Type" => "application/json"}, '{"error": "Rate limit exceeded"}']
        end

        allow(client).to receive(:connection).and_return(
          Faraday.new do |conn|
            conn.use SecApi::Middleware::ErrorHandler
            conn.adapter :test, stubs
          end
        )

        expect {
          extractor.extract(filing_url, item: :risk_factors)
        }.to raise_error(SecApi::RateLimitError)
      end
    end
  end
end
