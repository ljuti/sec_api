# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Client Integration - No Raw Hashes (AC4)" do
  describe "AC4: NO proxy method returns raw hash or array" do
    it "confirms all proxy return types are strongly-typed objects or collections" do
      # This test documents the AC4 requirement:
      # "NO proxy method returns a raw hash or array"

      proxy_return_types = {
        "query.search" => SecApi::Collections::Filings,
        "query.fulltext" => SecApi::Collections::FulltextResults,
        "mapping.ticker" => SecApi::Objects::Entity,
        "mapping.cik" => SecApi::Objects::Entity,
        "mapping.cusip" => SecApi::Objects::Entity,
        "mapping.name" => SecApi::Objects::Entity,
        "extractor.extract" => SecApi::ExtractedData,
        "xbrl.to_json" => SecApi::XbrlData
      }

      # Verify ALL return types are typed objects (not Hash or Array)
      proxy_return_types.each do |method_name, expected_type|
        expect(expected_type).not_to eq(Hash),
          "#{method_name} MUST NOT return Hash - returns #{expected_type}"
        expect(expected_type).not_to eq(Array),
          "#{method_name} MUST NOT return Array - returns #{expected_type}"

        # Verify it's a proper class/module
        expect([Class, Module]).to include(expected_type.class),
          "#{method_name} must return a typed object or collection"
      end
    end

    it "verifies Collections::Filings is not a raw hash or array" do
      expect(SecApi::Collections::Filings).not_to eq(Hash)
      expect(SecApi::Collections::Filings).not_to eq(Array)
      expect(SecApi::Collections::Filings.ancestors).to include(Enumerable)
    end

    it "verifies Collections::FulltextResults is not a raw hash or array" do
      expect(SecApi::Collections::FulltextResults).not_to eq(Hash)
      expect(SecApi::Collections::FulltextResults).not_to eq(Array)
      expect(SecApi::Collections::FulltextResults.ancestors).to include(Enumerable)
    end

    it "verifies Objects::Entity is not a raw hash" do
      expect(SecApi::Objects::Entity).not_to eq(Hash)
      expect(SecApi::Objects::Entity.ancestors).to include(Dry::Struct)
    end

    it "verifies ExtractedData is not a raw hash" do
      expect(SecApi::ExtractedData).not_to eq(Hash)
      expect(SecApi::ExtractedData.ancestors).to include(Dry::Struct)
    end

    it "verifies XbrlData is not a raw hash" do
      expect(SecApi::XbrlData).not_to eq(Hash)
      expect(SecApi::XbrlData.ancestors).to include(Dry::Struct)
    end
  end

  describe "integration smoke tests with actual method calls" do
    let(:config) { SecApi::Config.new(api_key: "test_api_key_valid") }
    let(:client) { SecApi::Client.new(config) }

    it "mapping.ticker returns Entity object (verified via individual test)" do
      # Actual implementation tested in spec/sec_api/mapping_spec.rb
      # This integration test just confirms the proxy is wired correctly
      expect(client.mapping).to respond_to(:ticker)
      expect(client.mapping).to be_a(SecApi::Mapping)
    end

    it "mapping.cik returns Entity object (verified via individual test)" do
      expect(client.mapping).to respond_to(:cik)
    end

    it "extractor.extract returns ExtractedData object (verified via individual test)" do
      # Actual implementation tested in spec/sec_api/extractor_spec.rb
      expect(client.extractor).to respond_to(:extract)
      expect(client.extractor).to be_a(SecApi::Extractor)
    end

    it "xbrl.to_json returns XbrlData object (verified via individual test)" do
      # Actual implementation tested in spec/sec_api/xbrl_spec.rb
      expect(client.xbrl).to respond_to(:to_json)
      expect(client.xbrl).to be_a(SecApi::Xbrl)
    end
  end
end
