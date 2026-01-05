# frozen_string_literal: true

require "spec_helper"

RSpec.describe SecApi::Mapping do
  let(:config) { SecApi::Config.new(api_key: "test_api_key_valid") }
  let(:client) { SecApi::Client.new(config) }
  let(:mapping) { client.mapping }

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

      allow(client).to receive(:connection).and_return(
        Faraday.new do |conn|
          conn.request :json
          conn.response :json, content_type: /\bjson$/, parser_options: {symbolize_names: true}
          conn.use SecApi::Middleware::ErrorHandler
          conn.adapter :test, stubs
        end
      )

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

      allow(client).to receive(:connection).and_return(
        Faraday.new do |conn|
          conn.request :json
          conn.response :json, content_type: /\bjson$/, parser_options: {symbolize_names: true}
          conn.use SecApi::Middleware::ErrorHandler
          conn.adapter :test, stubs
        end
      )

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

      allow(client).to receive(:connection).and_return(
        Faraday.new do |conn|
          conn.request :json
          conn.response :json, content_type: /\bjson$/, parser_options: {symbolize_names: true}
          conn.use SecApi::Middleware::ErrorHandler
          conn.adapter :test, stubs
        end
      )

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

      allow(client).to receive(:connection).and_return(
        Faraday.new do |conn|
          conn.request :json
          conn.response :json, content_type: /\bjson$/, parser_options: {symbolize_names: true}
          conn.use SecApi::Middleware::ErrorHandler
          conn.adapter :test, stubs
        end
      )

      entity = mapping.cik("0000320193")

      expect(entity).to be_a(SecApi::Objects::Entity)
      expect(entity.cik).to eq("0000320193")
      expect(entity.ticker).to eq("AAPL")
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

      allow(client).to receive(:connection).and_return(
        Faraday.new do |conn|
          conn.request :json
          conn.response :json, content_type: /\bjson$/, parser_options: {symbolize_names: true}
          conn.use SecApi::Middleware::ErrorHandler
          conn.adapter :test, stubs
        end
      )

      entity = mapping.cusip("037833100")

      expect(entity).to be_a(SecApi::Objects::Entity)
      expect(entity.cik).to eq("0000320193")
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

      allow(client).to receive(:connection).and_return(
        Faraday.new do |conn|
          conn.request :json
          conn.response :json, content_type: /\bjson$/, parser_options: {symbolize_names: true}
          conn.use SecApi::Middleware::ErrorHandler
          conn.adapter :test, stubs
        end
      )

      entity = mapping.cusip("037833100")

      expect(entity.cik).to eq("0000320193")
      expect(entity.ticker).to eq("AAPL")
      expect(entity.name).to eq("Apple Inc.")
      expect(entity.exchange).to eq("NASDAQ")
      stubs.verify_stubbed_calls
    end
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

      allow(client).to receive(:connection).and_return(
        Faraday.new do |conn|
          conn.request :json
          conn.response :json, content_type: /\bjson$/, parser_options: {symbolize_names: true}
          conn.use SecApi::Middleware::ErrorHandler
          conn.adapter :test, stubs
        end
      )

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

      allow(client).to receive(:connection).and_return(
        Faraday.new do |conn|
          conn.request :json
          conn.response :json, content_type: /\bjson$/, parser_options: {symbolize_names: true}
          conn.use SecApi::Middleware::ErrorHandler
          conn.adapter :test, stubs
        end
      )

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

      allow(client).to receive(:connection).and_return(
        Faraday.new do |conn|
          conn.request :json
          conn.response :json, content_type: /\bjson$/, parser_options: {symbolize_names: true}
          conn.use SecApi::Middleware::ErrorHandler
          conn.adapter :test, stubs
        end
      )

      expect { mapping.ticker("INVALID") }.to raise_error(SecApi::NotFoundError)
      stubs.verify_stubbed_calls
    end
  end
end
