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

    context "without sections parameter (default behavior)" do
      it "extracts full filing text when no sections specified" do
        stubs = Faraday::Adapter::Test::Stubs.new
        stubs.post("/extractor") do |env|
          body = JSON.parse(env.body)
          expect(body).not_to have_key("item")
          [200, {"Content-Type" => "application/json"}, {
            "text" => "Full filing text content with all sections",
            "sections" => {
              "risk_factors" => "Risk content",
              "mda" => "MD&A content"
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

        expect(extracted).to be_a(SecApi::ExtractedData)
        expect(extracted.text).to eq("Full filing text content with all sections")
        expect(extracted.sections).to include(:risk_factors, :mda)
        stubs.verify_stubbed_calls
      end

      it "extracts full filing when sections is empty array" do
        stubs = Faraday::Adapter::Test::Stubs.new
        stubs.post("/extractor") do |env|
          body = JSON.parse(env.body)
          expect(body).not_to have_key("item")
          [200, {"Content-Type" => "application/json"}, {
            "text" => "Full filing text"
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

        extracted = extractor.extract("https://example.com/filing.htm", sections: [])

        expect(extracted.text).to eq("Full filing text")
        stubs.verify_stubbed_calls
      end
    end

    context "with sections parameter" do
      it "extracts single section via item parameter" do
        stubs = Faraday::Adapter::Test::Stubs.new
        stubs.post("/extractor") do |env|
          body = JSON.parse(env.body)
          expect(body["item"]).to eq("1A")
          [200, {"Content-Type" => "application/json"}, {
            "text" => "Risk factors content from filing",
            "sections" => {"risk_factors" => "Risk factors content from filing"}
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

        extracted = extractor.extract("https://example.com/filing.htm", sections: [:risk_factors])

        expect(extracted).to be_a(SecApi::ExtractedData)
        expect(extracted.sections).to include(:risk_factors)
        stubs.verify_stubbed_calls
      end

      it "extracts multiple sections with separate API calls" do
        call_count = 0
        expected_items = ["1A", "7"]

        stubs = Faraday::Adapter::Test::Stubs.new
        stubs.post("/extractor") do |env|
          body = JSON.parse(env.body)
          expect(expected_items).to include(body["item"])
          call_count += 1

          section_name = (body["item"] == "1A") ? "risk_factors" : "mda"
          section_content = (body["item"] == "1A") ? "Risk factors text" : "MD&A analysis text"

          [200, {"Content-Type" => "application/json"}, {
            "text" => section_content,
            "sections" => {section_name => section_content}
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

        extracted = extractor.extract("https://example.com/filing.htm", sections: [:risk_factors, :mda])

        expect(extracted).to be_a(SecApi::ExtractedData)
        expect(extracted.sections.keys).to contain_exactly(:risk_factors, :mda)
        expect(call_count).to eq(2)
      end

      it "maps Ruby symbols to SEC item identifiers" do
        section_mappings = {
          risk_factors: "1A",
          business: "1",
          mda: "7",
          financials: "8",
          legal_proceedings: "3",
          properties: "2",
          market_risk: "7A"
        }

        section_mappings.each do |symbol, expected_item|
          stubs = Faraday::Adapter::Test::Stubs.new
          stubs.post("/extractor") do |env|
            body = JSON.parse(env.body)
            expect(body["item"]).to eq(expected_item), "Expected #{symbol} to map to #{expected_item}, got #{body["item"]}"
            [200, {"Content-Type" => "application/json"}, {
              "sections" => {symbol.to_s => "Content"}
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

          extractor.extract("https://example.com/filing.htm", sections: [symbol])
          stubs.verify_stubbed_calls
        end
      end

      it "passes through unknown section names as-is" do
        stubs = Faraday::Adapter::Test::Stubs.new
        stubs.post("/extractor") do |env|
          body = JSON.parse(env.body)
          expect(body["item"]).to eq("custom_section")
          [200, {"Content-Type" => "application/json"}, {
            "sections" => {"custom_section" => "Custom content"}
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

        extracted = extractor.extract("https://example.com/filing.htm", sections: [:custom_section])

        expect(extracted.sections).to include(:custom_section)
        stubs.verify_stubbed_calls
      end

      it "accepts string sections and converts to symbols" do
        stubs = Faraday::Adapter::Test::Stubs.new
        stubs.post("/extractor") do |env|
          body = JSON.parse(env.body)
          expect(body["item"]).to eq("1A")
          [200, {"Content-Type" => "application/json"}, {
            "sections" => {"risk_factors" => "Risk content from string input"}
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

        # Pass strings instead of symbols
        extracted = extractor.extract("https://example.com/filing.htm", sections: ["risk_factors"])

        expect(extracted.sections).to include(:risk_factors)
        expect(extracted.risk_factors).to eq("Risk content from string input")
        stubs.verify_stubbed_calls
      end

      it "propagates API errors during multi-section extraction" do
        call_count = 0
        stubs = Faraday::Adapter::Test::Stubs.new
        stubs.post("/extractor") do |env|
          call_count += 1
          body = JSON.parse(env.body)

          if body["item"] == "1A"
            # First section succeeds
            [200, {"Content-Type" => "application/json"}, {
              "sections" => {"risk_factors" => "Risk content"}
            }.to_json]
          else
            # Second section fails with rate limit
            [429, {"Content-Type" => "application/json"}, {
              "error" => "Rate limit exceeded"
            }.to_json]
          end
        end

        allow(client).to receive(:connection).and_return(
          Faraday.new do |conn|
            conn.request :json
            conn.response :json, content_type: /\bjson$/, parser_options: {symbolize_names: true}
            conn.use SecApi::Middleware::ErrorHandler
            conn.adapter :test, stubs
          end
        )

        # Should raise error, partial results lost
        expect {
          extractor.extract("https://example.com/filing.htm", sections: [:risk_factors, :mda])
        }.to raise_error(SecApi::RateLimitError)

        expect(call_count).to eq(2)
      end
    end

    context "with missing sections in filing" do
      it "returns nil for sections not present in filing" do
        stubs = Faraday::Adapter::Test::Stubs.new
        stubs.post("/extractor") do
          # API returns empty response when section doesn't exist
          [200, {"Content-Type" => "application/json"}, {
            "text" => nil,
            "sections" => {}
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

        extracted = extractor.extract("https://example.com/filing.htm", sections: [:nonexistent_section])

        # Section not in response should not appear in sections hash
        expect(extracted.sections).not_to have_key(:nonexistent_section)
        # Dynamic accessor returns nil for missing section
        expect(extracted.nonexistent_section).to be_nil
        stubs.verify_stubbed_calls
      end

      it "does not raise error when requested section is missing from filing" do
        stubs = Faraday::Adapter::Test::Stubs.new
        stubs.post("/extractor") do
          [200, {"Content-Type" => "application/json"}, {
            "sections" => nil
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

        # Should not raise an error
        expect {
          extractor.extract("https://example.com/filing.htm", sections: [:risk_factors])
        }.not_to raise_error

        stubs.verify_stubbed_calls
      end

      it "returns partial results when some sections exist and others don't" do
        call_count = 0
        stubs = Faraday::Adapter::Test::Stubs.new
        stubs.post("/extractor") do |env|
          call_count += 1
          body = JSON.parse(env.body)

          if body["item"] == "1A"
            # risk_factors exists
            [200, {"Content-Type" => "application/json"}, {
              "sections" => {"risk_factors" => "Risk content exists"}
            }.to_json]
          else
            # mda doesn't exist - empty response
            [200, {"Content-Type" => "application/json"}, {
              "sections" => {}
            }.to_json]
          end
        end

        allow(client).to receive(:connection).and_return(
          Faraday.new do |conn|
            conn.request :json
            conn.response :json, content_type: /\bjson$/, parser_options: {symbolize_names: true}
            conn.use SecApi::Middleware::ErrorHandler
            conn.adapter :test, stubs
          end
        )

        extracted = extractor.extract("https://example.com/filing.htm", sections: [:risk_factors, :mda])

        expect(extracted.risk_factors).to eq("Risk content exists")
        expect(extracted.mda).to be_nil
        expect(call_count).to eq(2)
      end
    end
  end
end
