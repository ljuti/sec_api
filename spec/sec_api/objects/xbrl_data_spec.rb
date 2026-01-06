# frozen_string_literal: true

require "spec_helper"

RSpec.describe SecApi::XbrlData do
  describe "structure and inheritance" do
    it "inherits from Dry::Struct" do
      expect(described_class).to be < Dry::Struct
    end

    it "creates instance with statement attributes" do
      xbrl_data = described_class.new(
        statements_of_income: {},
        balance_sheets: {},
        statements_of_cash_flows: {},
        cover_page: {}
      )

      expect(xbrl_data).to be_a(SecApi::XbrlData)
    end
  end

  describe "statement attributes" do
    let(:revenue_fact) do
      SecApi::Fact.new(
        value: "394328000000",
        decimals: "-6",
        unit_ref: "usd",
        period: SecApi::Period.new(start_date: "2022-09-25", end_date: "2023-09-30")
      )
    end

    let(:assets_fact) do
      SecApi::Fact.new(
        value: "352755000000",
        decimals: "-6",
        unit_ref: "usd",
        period: SecApi::Period.new(instant: "2023-09-30")
      )
    end

    it "accepts statements_of_income with Fact objects" do
      xbrl_data = described_class.new(
        statements_of_income: {
          "RevenueFromContractWithCustomerExcludingAssessedTax" => [revenue_fact]
        }
      )

      facts = xbrl_data.statements_of_income["RevenueFromContractWithCustomerExcludingAssessedTax"]
      expect(facts).to be_an(Array)
      expect(facts.first.value).to eq("394328000000")
    end

    it "accepts balance_sheets with Fact objects" do
      xbrl_data = described_class.new(
        balance_sheets: {"Assets" => [assets_fact]}
      )

      facts = xbrl_data.balance_sheets["Assets"]
      expect(facts.first.value).to eq("352755000000")
      expect(facts.first.period.instant?).to be true
    end

    it "accepts statements_of_cash_flows with Fact objects" do
      cash_flow_fact = SecApi::Fact.new(value: "96995000000")
      xbrl_data = described_class.new(
        statements_of_cash_flows: {"NetIncomeLoss" => [cash_flow_fact]}
      )

      facts = xbrl_data.statements_of_cash_flows["NetIncomeLoss"]
      expect(facts.first.to_numeric).to eq(96995000000.0)
    end

    it "accepts cover_page with Fact objects" do
      doc_type_fact = SecApi::Fact.new(value: "10-K")
      registrant_fact = SecApi::Fact.new(value: "Apple Inc")

      xbrl_data = described_class.new(
        cover_page: {
          "DocumentType" => [doc_type_fact],
          "EntityRegistrantName" => [registrant_fact]
        }
      )

      expect(xbrl_data.cover_page["DocumentType"].first.value).to eq("10-K")
      expect(xbrl_data.cover_page["EntityRegistrantName"].first.value).to eq("Apple Inc")
    end

    it "allows nil for all statement attributes" do
      xbrl_data = described_class.new
      expect(xbrl_data.statements_of_income).to be_nil
      expect(xbrl_data.balance_sheets).to be_nil
      expect(xbrl_data.statements_of_cash_flows).to be_nil
      expect(xbrl_data.cover_page).to be_nil
    end
  end

  describe "#valid?" do
    it "returns true (placeholder for Story 4.3 validation)" do
      xbrl_data = described_class.new(
        statements_of_income: {}
      )
      expect(xbrl_data.valid?).to be true
    end
  end

  describe "immutability" do
    let(:xbrl_data) do
      revenue_fact = SecApi::Fact.new(value: "1000000")
      described_class.new(
        statements_of_income: {"Revenue" => [revenue_fact]},
        balance_sheets: {"Assets" => [SecApi::Fact.new(value: "5000000")]}
      )
    end

    it "is frozen after initialization" do
      expect(xbrl_data).to be_frozen
    end

    it "has frozen statements_of_income hash" do
      expect(xbrl_data.statements_of_income).to be_frozen
    end

    it "has frozen balance_sheets hash" do
      expect(xbrl_data.balance_sheets).to be_frozen
    end

    it "raises error when trying to modify statements" do
      expect {
        xbrl_data.statements_of_income["NewElement"] = []
      }.to raise_error(FrozenError)
    end
  end

  describe ".from_api" do
    let(:api_response) do
      {
        StatementsOfIncome: {
          RevenueFromContractWithCustomerExcludingAssessedTax: [
            {value: "394328000000", decimals: "-6", unitRef: "usd", period: {startDate: "2022-09-25", endDate: "2023-09-30"}}
          ],
          CostOfGoodsAndServicesSold: [
            {value: "214137000000", decimals: "-6", unitRef: "usd", period: {startDate: "2022-09-25", endDate: "2023-09-30"}}
          ]
        },
        BalanceSheets: {
          Assets: [
            {value: "352755000000", decimals: "-6", unitRef: "usd", period: {instant: "2023-09-30"}}
          ]
        },
        StatementsOfCashFlows: {
          NetIncomeLoss: [
            {value: "96995000000", decimals: "-6", unitRef: "usd", period: {startDate: "2022-09-25", endDate: "2023-09-30"}}
          ]
        },
        CoverPage: {
          DocumentType: [{value: "10-K"}],
          EntityRegistrantName: [{value: "Apple Inc"}],
          DocumentPeriodEndDate: [{value: "2023-09-30"}]
        }
      }
    end

    it "parses API response into XbrlData object" do
      xbrl_data = described_class.from_api(api_response)

      expect(xbrl_data).to be_a(SecApi::XbrlData)
    end

    it "converts StatementsOfIncome to statements_of_income" do
      xbrl_data = described_class.from_api(api_response)

      revenue_facts = xbrl_data.statements_of_income["RevenueFromContractWithCustomerExcludingAssessedTax"]
      expect(revenue_facts).to be_an(Array)
      expect(revenue_facts.first).to be_a(SecApi::Fact)
      expect(revenue_facts.first.value).to eq("394328000000")
    end

    it "converts BalanceSheets to balance_sheets" do
      xbrl_data = described_class.from_api(api_response)

      assets_facts = xbrl_data.balance_sheets["Assets"]
      expect(assets_facts.first.value).to eq("352755000000")
      expect(assets_facts.first.period.instant?).to be true
    end

    it "converts StatementsOfCashFlows to statements_of_cash_flows" do
      xbrl_data = described_class.from_api(api_response)

      net_income_facts = xbrl_data.statements_of_cash_flows["NetIncomeLoss"]
      expect(net_income_facts.first.to_numeric).to eq(96995000000.0)
    end

    it "converts CoverPage to cover_page" do
      xbrl_data = described_class.from_api(api_response)

      expect(xbrl_data.cover_page["DocumentType"].first.value).to eq("10-K")
      expect(xbrl_data.cover_page["EntityRegistrantName"].first.value).to eq("Apple Inc")
    end

    it "preserves element names as-is (no snake_case conversion)" do
      xbrl_data = described_class.from_api(api_response)

      # Element names should remain in their original taxonomy format
      expect(xbrl_data.statements_of_income.keys).to include("RevenueFromContractWithCustomerExcludingAssessedTax")
      expect(xbrl_data.statements_of_income.keys).to include("CostOfGoodsAndServicesSold")
    end

    it "handles string keys from JSON parsing" do
      string_key_response = {
        "StatementsOfIncome" => {
          "Revenue" => [{"value" => "1000000"}]
        }
      }

      xbrl_data = described_class.from_api(string_key_response)
      expect(xbrl_data.statements_of_income["Revenue"].first.value).to eq("1000000")
    end

    it "handles missing statement sections gracefully" do
      partial_response = {
        StatementsOfIncome: {Revenue: [{value: "1000"}]}
      }

      xbrl_data = described_class.from_api(partial_response)

      expect(xbrl_data.statements_of_income).not_to be_nil
      expect(xbrl_data.balance_sheets).to be_nil
      expect(xbrl_data.statements_of_cash_flows).to be_nil
      expect(xbrl_data.cover_page).to be_nil
    end

    it "handles empty response" do
      xbrl_data = described_class.from_api({})

      expect(xbrl_data.statements_of_income).to be_nil
      expect(xbrl_data.balance_sheets).to be_nil
    end

    it "returns immutable XbrlData" do
      xbrl_data = described_class.from_api(api_response)
      expect(xbrl_data).to be_frozen
    end
  end

  describe "thread safety" do
    let(:xbrl_data) do
      revenue_fact = SecApi::Fact.new(value: "1000000")
      assets_fact = SecApi::Fact.new(value: "5000000")
      described_class.new(
        statements_of_income: {"Revenue" => [revenue_fact]},
        balance_sheets: {"Assets" => [assets_fact]}
      )
    end

    it "is thread-safe for concurrent reads" do
      threads = 10.times.map do
        Thread.new do
          100.times do
            xbrl_data.statements_of_income["Revenue"]
            xbrl_data.balance_sheets["Assets"]
          end
        end
      end

      expect { threads.each(&:join) }.not_to raise_error
    end

    it "maintains data integrity across concurrent access" do
      results = []
      threads = 10.times.map do
        Thread.new do
          xbrl_data.statements_of_income["Revenue"].first.value
        end
      end

      threads.each { |t| results << t.value }
      expect(results.uniq).to eq(["1000000"])
    end

    it "prevents concurrent modification attempts" do
      threads = 10.times.map do
        Thread.new do
          expect {
            xbrl_data.statements_of_income["NewElement"] = []
          }.to raise_error(FrozenError)
        end
      end

      expect { threads.each(&:join) }.not_to raise_error
    end
  end

  describe "#element_names" do
    let(:xbrl_data) do
      described_class.new(
        statements_of_income: {
          "RevenueFromContractWithCustomerExcludingAssessedTax" => [SecApi::Fact.new(value: "394328000000")],
          "CostOfGoodsAndServicesSold" => [SecApi::Fact.new(value: "214137000000")]
        },
        balance_sheets: {
          "Assets" => [SecApi::Fact.new(value: "352755000000")],
          "Liabilities" => [SecApi::Fact.new(value: "290020000000")]
        },
        statements_of_cash_flows: {
          "NetIncomeLoss" => [SecApi::Fact.new(value: "96995000000")]
        },
        cover_page: {
          "DocumentType" => [SecApi::Fact.new(value: "10-K")],
          "EntityRegistrantName" => [SecApi::Fact.new(value: "Apple Inc")]
        }
      )
    end

    it "returns all element names across all statements" do
      names = xbrl_data.element_names

      expect(names).to include("RevenueFromContractWithCustomerExcludingAssessedTax")
      expect(names).to include("CostOfGoodsAndServicesSold")
      expect(names).to include("Assets")
      expect(names).to include("Liabilities")
      expect(names).to include("NetIncomeLoss")
      expect(names).to include("DocumentType")
      expect(names).to include("EntityRegistrantName")
    end

    it "returns element names as an array" do
      expect(xbrl_data.element_names).to be_an(Array)
    end

    it "returns unique element names" do
      # Create xbrl_data with duplicate element names across statements
      xbrl_with_dups = described_class.new(
        statements_of_income: {"Revenue" => [SecApi::Fact.new(value: "100")]},
        balance_sheets: {"Revenue" => [SecApi::Fact.new(value: "100")]}
      )

      names = xbrl_with_dups.element_names
      expect(names.count("Revenue")).to eq(1)
    end

    it "returns sorted element names" do
      names = xbrl_data.element_names
      expect(names).to eq(names.sort)
    end

    it "returns empty array when no statements have data" do
      empty_xbrl = described_class.new
      expect(empty_xbrl.element_names).to eq([])
    end

    it "handles partially populated statements" do
      partial_xbrl = described_class.new(
        statements_of_income: {"Revenue" => [SecApi::Fact.new(value: "100")]}
      )

      expect(partial_xbrl.element_names).to eq(["Revenue"])
    end
  end

  describe "accessing non-existent elements (AC#5)" do
    let(:xbrl_data) do
      revenue_fact = SecApi::Fact.new(value: "394328000000")
      assets_fact = SecApi::Fact.new(value: "352755000000")
      described_class.new(
        statements_of_income: {"RevenueFromContractWithCustomerExcludingAssessedTax" => [revenue_fact]},
        balance_sheets: {"Assets" => [assets_fact]},
        statements_of_cash_flows: {"NetIncomeLoss" => [SecApi::Fact.new(value: "96995000000")]},
        cover_page: {"DocumentType" => [SecApi::Fact.new(value: "10-K")]}
      )
    end

    it "returns nil for non-existent element in statements_of_income" do
      expect(xbrl_data.statements_of_income["NonExistentElement"]).to be_nil
    end

    it "returns nil for non-existent element in balance_sheets" do
      expect(xbrl_data.balance_sheets["NonExistentElement"]).to be_nil
    end

    it "returns nil for non-existent element in statements_of_cash_flows" do
      expect(xbrl_data.statements_of_cash_flows["NonExistentElement"]).to be_nil
    end

    it "returns nil for non-existent element in cover_page" do
      expect(xbrl_data.cover_page["NonExistentElement"]).to be_nil
    end

    it "does not raise exception when accessing missing element" do
      expect { xbrl_data.statements_of_income["MissingElement"] }.not_to raise_error
      expect { xbrl_data.balance_sheets["MissingElement"] }.not_to raise_error
    end

    it "supports safe navigation pattern with nil statement" do
      empty_xbrl = described_class.new

      # Safe navigation when statement is nil
      result = empty_xbrl.statements_of_income&.[]("Revenue")
      expect(result).to be_nil
    end

    it "supports safe navigation pattern for nil element access" do
      # Safe navigation when element doesn't exist
      result = xbrl_data.statements_of_income["NonExistent"]&.first&.to_numeric
      expect(result).to be_nil
    end

    it "allows conditional checks before using facts" do
      facts = xbrl_data.statements_of_income["NonExistentElement"]

      # User can safely check for nil
      if facts
        expect(facts.first).to be_a(SecApi::Fact)
      else
        expect(facts).to be_nil
      end
    end
  end

  describe "accessing financial data" do
    let(:api_response) do
      {
        StatementsOfIncome: {
          RevenueFromContractWithCustomerExcludingAssessedTax: [
            {value: "394328000000", decimals: "-6", unitRef: "usd", period: {startDate: "2022-09-25", endDate: "2023-09-30"}},
            {value: "365817000000", decimals: "-6", unitRef: "usd", period: {startDate: "2021-09-26", endDate: "2022-09-24"}}
          ]
        },
        BalanceSheets: {
          Assets: [
            {value: "352755000000", decimals: "-6", unitRef: "usd", period: {instant: "2023-09-30"}},
            {value: "352583000000", decimals: "-6", unitRef: "usd", period: {instant: "2022-09-24"}}
          ]
        }
      }
    end

    it "allows access to multiple periods for same element" do
      xbrl_data = described_class.from_api(api_response)

      revenue_facts = xbrl_data.statements_of_income["RevenueFromContractWithCustomerExcludingAssessedTax"]
      expect(revenue_facts.length).to eq(2)
      expect(revenue_facts[0].to_numeric).to eq(394328000000.0)
      expect(revenue_facts[1].to_numeric).to eq(365817000000.0)
    end

    it "allows filtering facts by period" do
      xbrl_data = described_class.from_api(api_response)

      assets_facts = xbrl_data.balance_sheets["Assets"]
      latest = assets_facts.find { |f| f.period.instant == Date.new(2023, 9, 30) }

      expect(latest.to_numeric).to eq(352755000000.0)
    end
  end
end
