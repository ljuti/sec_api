# frozen_string_literal: true

require "dry-struct"

module SecApi
  # Immutable value object representing XBRL financial data extracted from SEC filings.
  #
  # This class uses Dry::Struct for type safety and immutability, ensuring thread-safe
  # access to financial data. All nested structures are deeply frozen to prevent modification.
  #
  # The structure mirrors the sec-api.io XBRL-to-JSON response format:
  # - statements_of_income: Income statement elements (e.g., Revenue, NetIncome)
  # - balance_sheets: Balance sheet elements (e.g., Assets, Liabilities)
  # - statements_of_cash_flows: Cash flow statement elements
  # - cover_page: Document and entity information (DEI taxonomy)
  #
  # @example Create XbrlData from API response
  #   xbrl_data = SecApi::XbrlData.from_api(api_response)
  #   revenue_facts = xbrl_data.statements_of_income["RevenueFromContractWithCustomerExcludingAssessedTax"]
  #   latest_revenue = revenue_facts.first.to_numeric # => 394328000000.0
  #
  # @example Access balance sheet data
  #   assets_facts = xbrl_data.balance_sheets["Assets"]
  #   assets_facts.each do |fact|
  #     puts "#{fact.period.instant}: #{fact.to_numeric}"
  #   end
  #
  # @example Access IFRS filing data (20-F, 40-F)
  #   # IFRS uses simpler element names than US GAAP
  #   xbrl_data = client.xbrl.to_json("https://www.sec.gov/path/to/20f-filing.htm")
  #
  #   # IFRS: "Revenue" vs US GAAP: "RevenueFromContractWithCustomerExcludingAssessedTax"
  #   revenue_facts = xbrl_data.statements_of_income["Revenue"]
  #   revenue_facts&.first&.to_numeric  # => 52896000000.0
  #
  #   # IFRS: "Equity" vs US GAAP: "StockholdersEquity"
  #   equity_facts = xbrl_data.balance_sheets["Equity"]
  #   equity_facts&.first&.to_numeric  # => 53087000000.0
  #
  #   # Use element_names to discover what's available
  #   xbrl_data.element_names.grep(/Revenue|Equity/)
  #   # => ["Equity", "Revenue"]
  #
  # @note Taxonomy Transparency - Element Names Are NOT Normalized
  #   This gem returns element names exactly as provided by sec-api.io, without any
  #   normalization between US GAAP and IFRS taxonomies. This design decision ensures:
  #
  #   - **Accuracy:** You see exactly what the company reported
  #   - **No data loss:** Taxonomy-specific nuances are preserved
  #   - **Predictability:** The gem never modifies financial data
  #
  #   Users are responsible for knowing which elements to access based on the filing's
  #   taxonomy. Use {#element_names} to discover available elements in any filing.
  #
  # @note US GAAP Taxonomy Common Elements
  #   US domestic filings (10-K, 10-Q) use US GAAP taxonomy with verbose element names:
  #
  #   **Income Statement:**
  #   - RevenueFromContractWithCustomerExcludingAssessedTax (revenue)
  #   - CostOfGoodsAndServicesSold (cost of goods sold)
  #   - NetIncomeLoss (net income)
  #   - GrossProfit (gross profit)
  #   - OperatingIncomeLoss (operating income)
  #
  #   **Balance Sheet:**
  #   - Assets (total assets)
  #   - Liabilities (total liabilities)
  #   - StockholdersEquity (shareholders' equity)
  #   - CashAndCashEquivalentsAtCarryingValue (cash)
  #   - AccountsReceivableNetCurrent (accounts receivable)
  #
  #   **Cash Flow Statement:**
  #   - NetCashProvidedByUsedInOperatingActivities (operating cash flow)
  #   - NetCashProvidedByUsedInInvestingActivities (investing cash flow)
  #   - NetCashProvidedByUsedInFinancingActivities (financing cash flow)
  #
  # @note IFRS Taxonomy Common Elements
  #   Foreign issuer filings (20-F, 40-F) often use IFRS taxonomy with simpler element names:
  #
  #   **Income Statement:**
  #   - Revenue (revenue)
  #   - CostOfSales (cost of sales)
  #   - ProfitLoss (net income/profit)
  #   - GrossProfit (gross profit)
  #
  #   **Balance Sheet:**
  #   - Assets (total assets - same as US GAAP)
  #   - Liabilities (total liabilities - same as US GAAP)
  #   - Equity (shareholders' equity - NOT StockholdersEquity)
  #
  #   **Cash Flow Statement:**
  #   - CashFlowsFromUsedInOperatingActivities (operating cash flow)
  #   - CashFlowsFromUsedInInvestingActivities (investing cash flow)
  #   - CashFlowsFromUsedInFinancingActivities (financing cash flow)
  #
  #   Note: Element names are NOT normalized between taxonomies. Users working with
  #   international filings should use {#element_names} to discover available elements.
  #
  # @see https://dry-rb.org/gems/dry-struct/ Dry::Struct documentation
  # @see https://sec-api.io/docs/xbrl-to-json sec-api.io XBRL-to-JSON API
  #
  class XbrlData < Dry::Struct
    include DeepFreezable

    # Transform keys to allow string or symbol input
    transform_keys(&:to_sym)

    # Statement hash type: element_name => Array of Fact objects
    StatementHash = Types::Hash.map(Types::String, Types::Array.of(Fact)).optional

    # Statements of income (income statement elements)
    attribute? :statements_of_income, StatementHash

    # Balance sheets (balance sheet elements)
    attribute? :balance_sheets, StatementHash

    # Statements of cash flows (cash flow statement elements)
    attribute? :statements_of_cash_flows, StatementHash

    # Cover page (document and entity information from DEI taxonomy)
    attribute? :cover_page, StatementHash

    # Checks if this XbrlData object has valid structure.
    #
    # Returns true if at least one financial statement section is present.
    # This method is useful for defensive programming when XbrlData objects
    # are created via the constructor directly (bypassing from_api validation).
    #
    # Note: Objects created via from_api are guaranteed valid, as validation
    # happens at construction time and raises ValidationError on failure.
    #
    # @return [Boolean] true if structure is valid, false otherwise
    #
    # @example Check validity before processing
    #   xbrl_data = client.xbrl.to_json(filing_url)
    #   if xbrl_data.valid?
    #     process_financial_data(xbrl_data)
    #   end
    #
    # @example Always true for from_api objects
    #   xbrl_data = XbrlData.from_api(response)  # Raises if invalid
    #   xbrl_data.valid?  # => true (guaranteed)
    #
    def valid?
      [statements_of_income, balance_sheets, statements_of_cash_flows, cover_page].any?
    end

    # Returns all unique element names across all financial statements.
    #
    # This method is essential for discovering what XBRL elements are available
    # in a filing. Element names vary by taxonomy (US GAAP vs IFRS) and by company.
    # The gem does NOT normalize element names between taxonomies.
    #
    # @return [Array<String>] Sorted, unique element names from all statements
    #
    # @example Discover available elements in US GAAP filing
    #   xbrl_data = client.xbrl.to_json(filing_url)
    #   xbrl_data.element_names
    #   # => ["Assets", "CostOfGoodsAndServicesSold", "DocumentType", ...]
    #
    # @example Search for revenue-related elements
    #   xbrl_data.element_names.grep(/Revenue/)
    #   # => ["RevenueFromContractWithCustomerExcludingAssessedTax", ...]
    #
    # @example Discover elements in IFRS filing (20-F, 40-F)
    #   ifrs_data = client.xbrl.to_json("https://www.sec.gov/path/to/20f.htm")
    #   ifrs_data.element_names.grep(/Revenue|Profit/)
    #   # => ["ProfitLoss", "Revenue"]  # Simpler names than US GAAP
    #
    # @note Use this method to understand what data is available before accessing
    #   specific elements. This is especially important for international filings
    #   where element names differ from US GAAP conventions.
    #
    def element_names
      names = []
      names.concat(statements_of_income.keys) if statements_of_income
      names.concat(balance_sheets.keys) if balance_sheets
      names.concat(statements_of_cash_flows.keys) if statements_of_cash_flows
      names.concat(cover_page.keys) if cover_page
      names.uniq.sort
    end

    # Attempts to detect the taxonomy used in this XBRL filing based on element names.
    #
    # This method uses heuristics to guess whether the filing uses US GAAP or IFRS
    # taxonomy. Detection is based on characteristic element name patterns:
    #
    # - **US GAAP indicators:** Verbose element names like "StockholdersEquity",
    #   "RevenueFromContractWithCustomerExcludingAssessedTax",
    #   "NetCashProvidedByUsedInOperatingActivities"
    #
    # - **IFRS indicators:** Simpler element names like "Equity", "Revenue",
    #   "ProfitLoss", "CashFlowsFromUsedInOperatingActivities"
    #
    # @return [Symbol] :us_gaap, :ifrs, or :unknown
    #
    # @example Detect taxonomy before processing
    #   xbrl_data = client.xbrl.to_json(filing_url)
    #   case xbrl_data.taxonomy_hint
    #   when :us_gaap
    #     revenue = xbrl_data.statements_of_income["RevenueFromContractWithCustomerExcludingAssessedTax"]
    #   when :ifrs
    #     revenue = xbrl_data.statements_of_income["Revenue"]
    #   else
    #     # Fall back to element_names discovery
    #     revenue_key = xbrl_data.element_names.find { |n| n.include?("Revenue") }
    #     revenue = xbrl_data.statements_of_income[revenue_key]
    #   end
    #
    # @note This is a best-effort heuristic and may not be 100% accurate.
    #   Some filings may use mixed element naming conventions or custom elements
    #   that don't clearly indicate either taxonomy. Always verify with {#element_names}
    #   when uncertain. For authoritative taxonomy information, refer to the filing's
    #   original XBRL instance document.
    #
    def taxonomy_hint
      names = element_names

      # US GAAP indicators - verbose, specific naming patterns
      us_gaap_patterns = [
        /StockholdersEquity/,
        /RevenueFromContractWithCustomer/,
        /CostOfGoodsAndServicesSold/,
        /NetCashProvidedByUsedIn/,
        /NetIncomeLoss/,
        /CommonStockSharesOutstanding/,
        /OperatingLeaseLiability/,
        /PropertyPlantAndEquipmentNet/
      ]

      # IFRS indicators - simpler, shorter naming patterns
      ifrs_patterns = [
        /\AEquity\z/,  # Exact match for "Equity" (vs "StockholdersEquity")
        /\ARevenue\z/,  # Exact match for "Revenue"
        /\AProfitLoss\z/,
        /\ACostOfSales\z/,
        /CashFlowsFromUsedIn/  # Substring match: IFRS variants like "CashFlowsFromUsedInOperatingActivities"
      ]

      us_gaap_score = us_gaap_patterns.count { |pattern| names.any? { |name| name.match?(pattern) } }
      ifrs_score = ifrs_patterns.count { |pattern| names.any? { |name| name.match?(pattern) } }

      return :us_gaap if us_gaap_score > ifrs_score && us_gaap_score > 0
      return :ifrs if ifrs_score > us_gaap_score && ifrs_score > 0
      :unknown
    end

    # Override constructor to ensure deep immutability
    def initialize(attributes)
      super
      deep_freeze(statements_of_income) if statements_of_income
      deep_freeze(balance_sheets) if balance_sheets
      deep_freeze(statements_of_cash_flows) if statements_of_cash_flows
      deep_freeze(cover_page) if cover_page
      freeze
    end

    # Parses sec-api.io XBRL-to-JSON response into an XbrlData object.
    #
    # @param data [Hash] API response with camelCase section keys
    # @return [XbrlData] Immutable XbrlData object
    #
    # @example
    #   response = {
    #     StatementsOfIncome: {
    #       RevenueFromContractWithCustomerExcludingAssessedTax: [
    #         {value: "394328000000", decimals: "-6", unitRef: "usd", period: {...}}
    #       ]
    #     },
    #     BalanceSheets: {...},
    #     StatementsOfCashFlows: {...},
    #     CoverPage: {...}
    #   }
    #   xbrl_data = XbrlData.from_api(response)
    #
    def self.from_api(data)
      statements_of_income = parse_statement_section(data, :StatementsOfIncome, "StatementsOfIncome")
      balance_sheets = parse_statement_section(data, :BalanceSheets, "BalanceSheets")
      statements_of_cash_flows = parse_statement_section(data, :StatementsOfCashFlows, "StatementsOfCashFlows")
      cover_page = parse_statement_section(data, :CoverPage, "CoverPage")

      validate_has_statements!(statements_of_income, balance_sheets, statements_of_cash_flows, cover_page, data)

      new(
        statements_of_income: statements_of_income,
        balance_sheets: balance_sheets,
        statements_of_cash_flows: statements_of_cash_flows,
        cover_page: cover_page
      )
    end

    # Validates that at least one financial statement section is present.
    #
    # @param statements_of_income [Hash, nil] Parsed income statement
    # @param balance_sheets [Hash, nil] Parsed balance sheet
    # @param statements_of_cash_flows [Hash, nil] Parsed cash flow statement
    # @param cover_page [Hash, nil] Parsed cover page
    # @param original_data [Hash] Original API response for error context
    # @raise [ValidationError] when all statement sections are nil
    #
    def self.validate_has_statements!(statements_of_income, balance_sheets, statements_of_cash_flows, cover_page, original_data)
      has_any_statement = [statements_of_income, balance_sheets, statements_of_cash_flows, cover_page].any?

      return if has_any_statement

      raise ValidationError, "XBRL response contains no financial statements. " \
        "Expected at least one of: StatementsOfIncome, BalanceSheets, StatementsOfCashFlows, CoverPage. " \
        "Received keys: #{original_data.keys.inspect}"
    end

    private_class_method :validate_has_statements!

    # Parses a statement section from API response.
    #
    # @param data [Hash] Full API response
    # @param symbol_key [Symbol] Symbol key for the section
    # @param string_key [String] String key for the section
    # @return [Hash, nil] Parsed section or nil if not present
    #
    def self.parse_statement_section(data, symbol_key, string_key)
      section = data[symbol_key] || data[string_key]
      return nil if section.nil?

      result = {}
      section.each do |element_name, facts_array|
        # Convert element name to string (preserve original taxonomy name)
        element_key = element_name.to_s
        result[element_key] = facts_array.map { |fact_data| Fact.from_api(fact_data) }
      end
      result
    end

    private_class_method :parse_statement_section
  end
end
