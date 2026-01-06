# frozen_string_literal: true

require "spec_helper"

RSpec.describe SecApi::ExtractedData do
  describe "initialization" do
    it "accepts text, sections, and metadata attributes" do
      data = described_class.new(
        text: "Sample extracted text",
        sections: {risk_factors: "Risk section content"},
        metadata: {source_url: "https://example.com"}
      )

      expect(data.text).to eq("Sample extracted text")
      expect(data.sections).to eq({risk_factors: "Risk section content"})
      expect(data.metadata).to eq({source_url: "https://example.com"})
    end

    it "accepts nil for all optional attributes" do
      data = described_class.new(text: nil, sections: nil, metadata: nil)

      expect(data.text).to be_nil
      expect(data.sections).to be_nil
      expect(data.metadata).to be_nil
    end

    it "accepts partial attributes" do
      data = described_class.new(text: "Only text")

      expect(data.text).to eq("Only text")
      expect(data.sections).to be_nil
      expect(data.metadata).to be_nil
    end
  end

  describe "inheritance" do
    it "inherits from Dry::Struct" do
      data = described_class.new(text: "Test")
      expect(data).to be_a(Dry::Struct)
    end
  end

  describe "immutability" do
    it "is frozen after initialization" do
      data = described_class.new(text: "Sample")
      expect(data).to be_frozen
    end

    it "freezes nested sections hash" do
      data = described_class.new(
        sections: {risk_factors: "Risk content"}
      )
      expect(data.sections).to be_frozen if data.sections
    end

    it "does not provide setter methods" do
      data = described_class.new(text: "Sample")
      expect(data).not_to respond_to(:text=)
      expect(data).not_to respond_to(:sections=)
      expect(data).not_to respond_to(:metadata=)
    end
  end

  describe "schema flexibility" do
    it "ignores unknown attributes (uses attribute? for optional)" do
      # With attribute?, unknown keys are silently ignored (not strict)
      data = described_class.new(
        text: "Sample",
        unknown_field: "Ignored"
      )
      expect(data.text).to eq("Sample")
    end
  end

  describe ".from_api" do
    it "normalizes string keys to symbols" do
      api_response = {
        "text" => "API text",
        "sections" => {"risk_factors" => "Risk content"},
        "metadata" => {"source_url" => "https://example.com"}
      }

      data = described_class.from_api(api_response)

      expect(data.text).to eq("API text")
      expect(data.sections).to eq({risk_factors: "Risk content"})
      expect(data.metadata).to eq({"source_url" => "https://example.com"})
    end

    it "handles symbol keys from API" do
      api_response = {
        text: "API text",
        sections: {risk_factors: "Risk content"}
      }

      data = described_class.from_api(api_response)

      expect(data.text).to eq("API text")
      expect(data.sections).to eq({risk_factors: "Risk content"})
    end

    it "handles missing sections gracefully" do
      api_response = {"text" => "Only text"}

      data = described_class.from_api(api_response)

      expect(data.text).to eq("Only text")
      expect(data.sections).to be_nil
    end

    it "provides default empty hash for metadata if missing" do
      api_response = {"text" => "Only text"}

      data = described_class.from_api(api_response)

      expect(data.metadata).to eq({})
    end
  end

  describe "thread safety" do
    it "is thread-safe for concurrent access" do
      data = described_class.new(
        text: "Sample extracted text",
        sections: {risk_factors: "Risk section content"}
      )

      # Spawn 10 threads accessing the same object
      threads = 10.times.map do
        Thread.new do
          100.times do
            data.text
            data.sections[:risk_factors] if data.sections
            data.risk_factors  # Also test dynamic accessor
            data.metadata
          end
        end
      end

      # All threads complete without errors
      expect { threads.each(&:join) }.not_to raise_error
    end

    it "freezes text attribute for thread safety" do
      data = described_class.new(text: "Original text")
      expect(data.text).to be_frozen
    end
  end

  describe "dynamic section accessors" do
    context "with sections present" do
      let(:data) do
        described_class.new(
          sections: {
            risk_factors: "Risk factors content",
            mda: "MD&A analysis content",
            financials: "Financial statements"
          }
        )
      end

      it "provides accessor method for known sections" do
        expect(data.risk_factors).to eq("Risk factors content")
        expect(data.mda).to eq("MD&A analysis content")
        expect(data.financials).to eq("Financial statements")
      end

      it "responds to section names" do
        expect(data).to respond_to(:risk_factors)
        expect(data).to respond_to(:mda)
        expect(data).to respond_to(:financials)
      end

      it "returns nil for sections not in the hash" do
        expect(data.nonexistent_section).to be_nil
      end

      it "does not respond to nonexistent sections" do
        expect(data).not_to respond_to(:nonexistent_section)
      end
    end

    context "with nil sections" do
      let(:data) { described_class.new(text: "Only text", sections: nil) }

      it "returns nil for any section accessor" do
        expect(data.risk_factors).to be_nil
        expect(data.any_section).to be_nil
      end

      it "does not respond to section names when sections is nil" do
        expect(data).not_to respond_to(:risk_factors)
      end
    end

    context "with empty sections" do
      let(:data) { described_class.new(sections: {}) }

      it "returns nil for any section accessor" do
        expect(data.risk_factors).to be_nil
      end

      it "does not respond to section names when sections is empty" do
        expect(data).not_to respond_to(:risk_factors)
      end
    end

    it "still raises NoMethodError for truly undefined methods" do
      data = described_class.new(sections: {risk_factors: "Content"})
      # Methods that don't look like section access should still error
      expect { data.completely_undefined_object_method! }.to raise_error(NoMethodError)
    end
  end
end
