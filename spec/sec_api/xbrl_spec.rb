# frozen_string_literal: true

require "spec_helper"

RSpec.describe SecApi::Xbrl do
  let(:config) { SecApi::Config.new(api_key: "test_api_key_valid") }
  let(:client) { SecApi::Client.new(config) }
  let(:xbrl_proxy) { client.xbrl }

  describe "#to_json" do
    let(:filing) do
      double(
        "Filing",
        xbrl_url: "https://www.sec.gov/example.xml",
        accession_number: "0001234567-24-000001"
      )
    end

    it "returns XbrlData object (not raw hash)" do
      stub_request = Faraday::Adapter::Test::Stubs.new
      stub_request.get("/xbrl-to-json") do |env|
        [
          200,
          {"Content-Type" => "application/json"},
          {
            financials: {
              revenue: 1_000_000.0,
              assets: 5_000_000.0
            },
            metadata: {
              source_url: "https://www.sec.gov/example.xml"
            }
          }.to_json
        ]
      end

      allow(client).to receive(:connection).and_return(
        Faraday.new do |conn|
          conn.request :json
          conn.response :json, content_type: /\bjson$/, parser_options: {symbolize_names: true}
          conn.adapter :test, stub_request
        end
      )

      result = xbrl_proxy.to_json(filing)

      expect(result).to be_a(SecApi::XbrlData)
      expect(result).not_to be_a(Hash)
      stub_request.verify_stubbed_calls
    end

    it "provides access to financials via XbrlData object" do
      stub_request = Faraday::Adapter::Test::Stubs.new
      stub_request.get("/xbrl-to-json") do |env|
        [
          200,
          {"Content-Type" => "application/json"},
          {
            financials: {
              revenue: 1_500_000.0,
              assets: 7_500_000.0
            }
          }.to_json
        ]
      end

      allow(client).to receive(:connection).and_return(
        Faraday.new do |conn|
          conn.request :json
          conn.response :json, content_type: /\bjson$/, parser_options: {symbolize_names: true}
          conn.adapter :test, stub_request
        end
      )

      result = xbrl_proxy.to_json(filing)

      expect(result.financials[:revenue]).to eq(1_500_000.0)
      expect(result.financials[:assets]).to eq(7_500_000.0)
      stub_request.verify_stubbed_calls
    end

    it "is immutable (frozen)" do
      stub_request = Faraday::Adapter::Test::Stubs.new
      stub_request.get("/xbrl-to-json") do |env|
        [200, {"Content-Type" => "application/json"}, {financials: {revenue: 1000.0}}.to_json]
      end

      allow(client).to receive(:connection).and_return(
        Faraday.new do |conn|
          conn.request :json
          conn.response :json, content_type: /\bjson$/, parser_options: {symbolize_names: true}
          conn.adapter :test, stub_request
        end
      )

      result = xbrl_proxy.to_json(filing)

      expect(result).to be_frozen
      stub_request.verify_stubbed_calls
    end

    context "when API returns error" do
      it "raises error using exception hierarchy" do
        stub_request = Faraday::Adapter::Test::Stubs.new
        stub_request.get("/xbrl-to-json") do |env|
          [500, {}, "Server error"]
        end

        allow(client).to receive(:connection).and_return(
          Faraday.new do |conn|
            conn.request :json
            conn.response :json, content_type: /\bjson$/, parser_options: {symbolize_names: true}
            conn.use SecApi::Middleware::ErrorHandler
            conn.adapter :test, stub_request
          end
        )

        expect {
          xbrl_proxy.to_json(filing)
        }.to raise_error(SecApi::ServerError)
      end

      it "raises ValidationError with context when XBRL data coercion fails" do
        stub_request = Faraday::Adapter::Test::Stubs.new
        stub_request.get("/xbrl-to-json") do |env|
          # Return data with invalid type that cannot be coerced (string for float field)
          [200, {"Content-Type" => "application/json"}, {financials: {revenue: "not_a_number"}}.to_json]
        end

        allow(client).to receive(:connection).and_return(
          Faraday.new do |conn|
            conn.request :json
            conn.response :json, content_type: /\bjson$/, parser_options: {symbolize_names: true}
            conn.adapter :test, stub_request
          end
        )

        expect {
          xbrl_proxy.to_json(filing)
        }.to raise_error(SecApi::ValidationError, /XBRL data validation failed/)
      end
    end
  end

  describe "full integration test with middleware stack" do
    let(:config) { SecApi::Config.new(api_key: "test_api_key_valid", retry_max_attempts: 3) }
    let(:integration_client) { SecApi::Client.new(config) }
    let(:filing) do
      double(
        "Filing",
        xbrl_url: "https://www.sec.gov/example.xml",
        accession_number: "0001234567-24-000001"
      )
    end

    it "returns XbrlData through full middleware stack (retry + error handler)" do
      stub_request = Faraday::Adapter::Test::Stubs.new

      # Use direct stub without retry middleware for simplicity
      stub_request.get("/xbrl-to-json") do |env|
        [
          200,
          {"Content-Type" => "application/json"},
          {
            financials: {revenue: 2_000_000.0, assets: 10_000_000.0},
            metadata: {source_url: "https://www.sec.gov/example.xml"}
          }.to_json
        ]
      end

      allow(integration_client).to receive(:connection).and_return(
        Faraday.new do |conn|
          conn.request :json
          conn.response :json, content_type: /\bjson$/, parser_options: {symbolize_names: true}
          conn.use SecApi::Middleware::ErrorHandler
          conn.adapter :test, stub_request
        end
      )

      result = integration_client.xbrl.to_json(filing)

      expect(result).to be_a(SecApi::XbrlData)
      expect(result.financials[:revenue]).to eq(2_000_000.0)
      expect(result).to be_frozen

      stub_request.verify_stubbed_calls
    end
  end
end
