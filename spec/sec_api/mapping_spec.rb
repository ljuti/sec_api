# frozen_string_literal: true

require "spec_helper"

RSpec.describe SecApi::Mapping do
  let(:config) { SecApi::Config.new(api_key: "test_api_key_valid") }
  let(:client) { SecApi::Client.new(config) }
  let(:mapping) { client.mapping }

  # Shared helper to build Faraday connection with test stubs
  def stub_connection(stubs)
    allow(client).to receive(:connection).and_return(
      Faraday.new do |conn|
        conn.request :json
        conn.response :json, content_type: /\bjson$/, parser_options: {symbolize_names: true}
        conn.use SecApi::Middleware::ErrorHandler
        conn.adapter :test, stubs
      end
    )
  end

  describe "#ticker" do
    it "returns Entity object (not raw hash)" do
      stubs = Faraday::Adapter::Test::Stubs.new
      stubs.get("/mapping/ticker/AAPL") do
        [200, {"Content-Type" => "application/json"}, {
          "cik" => "0000320193",
          "ticker" => "AAPL",
          "name" => "Apple Inc.",
          "exchange" => "NASDAQ"
        }.to_json]
      end
      stub_connection(stubs)

      entity = mapping.ticker("AAPL")

      expect(entity).to be_a(SecApi::Objects::Entity)
      expect(entity).not_to be_a(Hash)
      stubs.verify_stubbed_calls
    end

    it "provides access to attributes via methods (not hash keys)" do
      stubs = Faraday::Adapter::Test::Stubs.new
      stubs.get("/mapping/ticker/AAPL") do
        [200, {"Content-Type" => "application/json"}, {
          "cik" => "0000320193",
          "ticker" => "AAPL",
          "name" => "Apple Inc."
        }.to_json]
      end
      stub_connection(stubs)

      entity = mapping.ticker("AAPL")

      expect(entity.cik).to eq("0000320193")
      expect(entity.ticker).to eq("AAPL")
      expect(entity.name).to eq("Apple Inc.")
      stubs.verify_stubbed_calls
    end

    it "is immutable (frozen)" do
      stubs = Faraday::Adapter::Test::Stubs.new
      stubs.get("/mapping/ticker/AAPL") do
        [200, {"Content-Type" => "application/json"}, {
          "cik" => "0000320193",
          "ticker" => "AAPL"
        }.to_json]
      end
      stub_connection(stubs)

      entity = mapping.ticker("AAPL")

      expect(entity).to be_frozen
      stubs.verify_stubbed_calls
    end
  end

  describe "#cik" do
    it "returns Entity object (not raw hash)" do
      stubs = Faraday::Adapter::Test::Stubs.new
      stubs.get("/mapping/cik/0000320193") do
        [200, {"Content-Type" => "application/json"}, {
          "cik" => "0000320193",
          "ticker" => "AAPL",
          "name" => "Apple Inc."
        }.to_json]
      end
      stub_connection(stubs)

      entity = mapping.cik("0000320193")

      expect(entity).to be_a(SecApi::Objects::Entity)
      expect(entity.cik).to eq("0000320193")
      expect(entity.ticker).to eq("AAPL")
      stubs.verify_stubbed_calls
    end

    it "provides bidirectional resolution (both cik and ticker accessible)" do
      stubs = Faraday::Adapter::Test::Stubs.new
      stubs.get("/mapping/cik/0000320193") do
        [200, {"Content-Type" => "application/json"}, {
          "cik" => "0000320193",
          "ticker" => "AAPL",
          "name" => "Apple Inc.",
          "exchange" => "NASDAQ"
        }.to_json]
      end
      stub_connection(stubs)

      entity = mapping.cik("0000320193")

      expect(entity.cik).to eq("0000320193")
      expect(entity.ticker).to eq("AAPL")
      expect(entity.name).to eq("Apple Inc.")
      expect(entity.exchange).to eq("NASDAQ")
      stubs.verify_stubbed_calls
    end

    it "is immutable (frozen)" do
      stubs = Faraday::Adapter::Test::Stubs.new
      stubs.get("/mapping/cik/0000320193") do
        [200, {"Content-Type" => "application/json"}, {
          "cik" => "0000320193",
          "ticker" => "AAPL"
        }.to_json]
      end
      stub_connection(stubs)

      entity = mapping.cik("0000320193")

      expect(entity).to be_frozen
      stubs.verify_stubbed_calls
    end

    context "CIK normalization" do
      it "normalizes CIK without leading zeros (320193 -> 0000320193)" do
        stubs = Faraday::Adapter::Test::Stubs.new
        stubs.get("/mapping/cik/0000320193") do
          [200, {"Content-Type" => "application/json"}, {
            "cik" => "0000320193",
            "ticker" => "AAPL",
            "name" => "Apple Inc."
          }.to_json]
        end
        stub_connection(stubs)

        entity = mapping.cik("320193")

        expect(entity.cik).to eq("0000320193")
        expect(entity.ticker).to eq("AAPL")
        stubs.verify_stubbed_calls
      end

      it "normalizes CIK with partial leading zeros (00320193 -> 0000320193)" do
        stubs = Faraday::Adapter::Test::Stubs.new
        stubs.get("/mapping/cik/0000320193") do
          [200, {"Content-Type" => "application/json"}, {
            "cik" => "0000320193",
            "ticker" => "AAPL"
          }.to_json]
        end
        stub_connection(stubs)

        entity = mapping.cik("00320193")

        expect(entity.cik).to eq("0000320193")
        stubs.verify_stubbed_calls
      end

      it "leaves already-normalized CIK unchanged" do
        stubs = Faraday::Adapter::Test::Stubs.new
        stubs.get("/mapping/cik/0000320193") do
          [200, {"Content-Type" => "application/json"}, {
            "cik" => "0000320193",
            "ticker" => "AAPL"
          }.to_json]
        end
        stub_connection(stubs)

        entity = mapping.cik("0000320193")

        expect(entity.cik).to eq("0000320193")
        stubs.verify_stubbed_calls
      end

      it "handles integer input gracefully" do
        stubs = Faraday::Adapter::Test::Stubs.new
        stubs.get("/mapping/cik/0000320193") do
          [200, {"Content-Type" => "application/json"}, {
            "cik" => "0000320193",
            "ticker" => "AAPL"
          }.to_json]
        end
        stub_connection(stubs)

        entity = mapping.cik(320193)

        expect(entity.cik).to eq("0000320193")
        stubs.verify_stubbed_calls
      end

      it "normalizes integer zero to all-zeros CIK" do
        stubs = Faraday::Adapter::Test::Stubs.new
        stubs.get("/mapping/cik/0000000000") do
          [404, {"Content-Type" => "application/json"}, {"error" => "CIK not found"}.to_json]
        end
        stub_connection(stubs)

        expect { mapping.cik(0) }.to raise_error(SecApi::NotFoundError)
        stubs.verify_stubbed_calls
      end
    end

    it "raises NotFoundError for invalid CIK with descriptive message" do
      stubs = Faraday::Adapter::Test::Stubs.new
      stubs.get("/mapping/cik/0000000000") do
        [404, {"Content-Type" => "application/json"}, {"error" => "CIK not found"}.to_json]
      end
      stub_connection(stubs)

      expect { mapping.cik("0000000000") }.to raise_error(SecApi::NotFoundError) do |error|
        expect(error.message).to include("not found")
        expect(error.message).to include("/mapping/cik/0000000000")
      end
      stubs.verify_stubbed_calls
    end
  end

  describe "#cusip" do
    it "returns Entity object (not raw hash)" do
      stubs = Faraday::Adapter::Test::Stubs.new
      stubs.get("/mapping/cusip/037833100") do
        [200, {"Content-Type" => "application/json"}, {
          "cik" => "0000320193",
          "ticker" => "AAPL",
          "name" => "Apple Inc."
        }.to_json]
      end
      stub_connection(stubs)

      entity = mapping.cusip("037833100")

      expect(entity).to be_a(SecApi::Objects::Entity)
      expect(entity.cik).to eq("0000320193")
      expect(entity.cusip).to be_nil # cusip not in API response
      stubs.verify_stubbed_calls
    end

    it "provides access to attributes via methods (not hash keys)" do
      stubs = Faraday::Adapter::Test::Stubs.new
      stubs.get("/mapping/cusip/037833100") do
        [200, {"Content-Type" => "application/json"}, {
          "cik" => "0000320193",
          "ticker" => "AAPL",
          "name" => "Apple Inc.",
          "exchange" => "NASDAQ"
        }.to_json]
      end
      stub_connection(stubs)

      entity = mapping.cusip("037833100")

      expect(entity.cik).to eq("0000320193")
      expect(entity.ticker).to eq("AAPL")
      expect(entity.name).to eq("Apple Inc.")
      expect(entity.exchange).to eq("NASDAQ")
      stubs.verify_stubbed_calls
    end

    it "returns Entity with cusip attribute populated" do
      stubs = Faraday::Adapter::Test::Stubs.new
      stubs.get("/mapping/cusip/037833100") do
        [200, {"Content-Type" => "application/json"}, {
          "cik" => "0000320193",
          "ticker" => "AAPL",
          "name" => "Apple Inc.",
          "cusip" => "037833100"
        }.to_json]
      end
      stub_connection(stubs)

      entity = mapping.cusip("037833100")

      expect(entity.cusip).to eq("037833100")
      stubs.verify_stubbed_calls
    end

    it "is immutable (frozen)" do
      stubs = Faraday::Adapter::Test::Stubs.new
      stubs.get("/mapping/cusip/037833100") do
        [200, {"Content-Type" => "application/json"}, {
          "cik" => "0000320193",
          "ticker" => "AAPL",
          "cusip" => "037833100"
        }.to_json]
      end
      stub_connection(stubs)

      entity = mapping.cusip("037833100")

      expect(entity).to be_frozen
      stubs.verify_stubbed_calls
    end

    it "raises NotFoundError for invalid CUSIP with descriptive message" do
      stubs = Faraday::Adapter::Test::Stubs.new
      stubs.get("/mapping/cusip/000000000") do
        [404, {"Content-Type" => "application/json"}, {"error" => "CUSIP not found"}.to_json]
      end
      stub_connection(stubs)

      expect { mapping.cusip("000000000") }.to raise_error(SecApi::NotFoundError) do |error|
        expect(error.message).to include("not found")
        expect(error.message).to include("/mapping/cusip/000000000")
      end
      stubs.verify_stubbed_calls
    end

    # NOTE: Edge case - CUSIPs mapping to multiple entities
    # The sec-api.io API returns the primary/most active entity by default.
    # Our implementation delegates to the API, so this behavior is inherited.
    # No additional handling required - API handles entity disambiguation.
  end

  describe "#name" do
    it "returns Entity object (not raw hash)" do
      stubs = Faraday::Adapter::Test::Stubs.new
      stubs.get("/mapping/name/Apple") do
        [200, {"Content-Type" => "application/json"}, {
          "cik" => "0000320193",
          "ticker" => "AAPL",
          "name" => "Apple Inc."
        }.to_json]
      end
      stub_connection(stubs)

      entity = mapping.name("Apple")

      expect(entity).to be_a(SecApi::Objects::Entity)
      expect(entity.name).to eq("Apple Inc.")
      stubs.verify_stubbed_calls
    end

    it "provides access to attributes via methods (not hash keys)" do
      stubs = Faraday::Adapter::Test::Stubs.new
      stubs.get("/mapping/name/Microsoft") do
        [200, {"Content-Type" => "application/json"}, {
          "cik" => "0000789019",
          "ticker" => "MSFT",
          "name" => "Microsoft Corporation",
          "exchange" => "NASDAQ"
        }.to_json]
      end
      stub_connection(stubs)

      entity = mapping.name("Microsoft")

      expect(entity.cik).to eq("0000789019")
      expect(entity.ticker).to eq("MSFT")
      expect(entity.name).to eq("Microsoft Corporation")
      expect(entity.exchange).to eq("NASDAQ")
      stubs.verify_stubbed_calls
    end
  end

  describe "error handling through middleware" do
    it "raises typed exceptions through middleware stack" do
      stubs = Faraday::Adapter::Test::Stubs.new
      stubs.get("/mapping/ticker/INVALID") do
        [404, {"Content-Type" => "application/json"}, {"error" => "Not found"}.to_json]
      end
      stub_connection(stubs)

      expect { mapping.ticker("INVALID") }.to raise_error(SecApi::NotFoundError)
      stubs.verify_stubbed_calls
    end
  end

  describe "input validation" do
    it "raises ValidationError when ticker is nil" do
      expect { mapping.ticker(nil) }.to raise_error(SecApi::ValidationError) do |error|
        expect(error.message).to include("ticker")
        expect(error.message).to include("required")
      end
    end

    it "raises ValidationError when ticker is empty string" do
      expect { mapping.ticker("") }.to raise_error(SecApi::ValidationError)
    end

    it "raises ValidationError when ticker is whitespace only" do
      expect { mapping.ticker("   ") }.to raise_error(SecApi::ValidationError)
    end

    it "raises ValidationError when CIK is nil" do
      expect { mapping.cik(nil) }.to raise_error(SecApi::ValidationError) do |error|
        expect(error.message).to include("CIK")
      end
    end

    it "raises ValidationError when CUSIP is nil" do
      expect { mapping.cusip(nil) }.to raise_error(SecApi::ValidationError) do |error|
        expect(error.message).to include("CUSIP")
        expect(error.message).to include("required")
      end
    end

    it "raises ValidationError when CUSIP is empty" do
      expect { mapping.cusip("") }.to raise_error(SecApi::ValidationError) do |error|
        expect(error.message).to include("CUSIP")
      end
    end

    it "raises ValidationError when CUSIP is whitespace only" do
      expect { mapping.cusip("   ") }.to raise_error(SecApi::ValidationError)
    end

    it "raises ValidationError when name is nil" do
      expect { mapping.name(nil) }.to raise_error(SecApi::ValidationError) do |error|
        expect(error.message).to include("name")
      end
    end
  end

  describe "URL encoding" do
    it "encodes ticker with dot (BRK.A)" do
      stubs = Faraday::Adapter::Test::Stubs.new
      stubs.get("/mapping/ticker/BRK.A") do
        [200, {"Content-Type" => "application/json"}, {
          "cik" => "0001067983",
          "ticker" => "BRK.A",
          "name" => "Berkshire Hathaway Inc."
        }.to_json]
      end
      stub_connection(stubs)

      entity = mapping.ticker("BRK.A")

      expect(entity.ticker).to eq("BRK.A")
      stubs.verify_stubbed_calls
    end

    it "encodes company name with spaces" do
      stubs = Faraday::Adapter::Test::Stubs.new
      stubs.get("/mapping/name/Apple+Inc") do
        [200, {"Content-Type" => "application/json"}, {
          "cik" => "0000320193",
          "ticker" => "AAPL",
          "name" => "Apple Inc."
        }.to_json]
      end
      stub_connection(stubs)

      entity = mapping.name("Apple Inc")

      expect(entity.name).to eq("Apple Inc.")
      stubs.verify_stubbed_calls
    end

    it "encodes special characters in identifiers" do
      stubs = Faraday::Adapter::Test::Stubs.new
      stubs.get("/mapping/name/AT%26T") do
        [200, {"Content-Type" => "application/json"}, {
          "cik" => "0000732717",
          "ticker" => "T",
          "name" => "AT&T Inc."
        }.to_json]
      end
      stub_connection(stubs)

      entity = mapping.name("AT&T")

      expect(entity.name).to eq("AT&T Inc.")
      stubs.verify_stubbed_calls
    end
  end
end
