#!/usr/bin/env ruby
# frozen_string_literal: true

# Example: Query Builder DSL
#
# This example demonstrates:
# - Querying filings by ticker symbol(s)
# - Querying by CIK number
# - Filtering by form type (domestic and international)
# - Filtering by date range
# - Full-text search
# - Combining multiple filters
# - Limiting results
# - Manual pagination with fetch_next_page
#
# Prerequisites:
# - gem install sec_api
# - Set SECAPI_API_KEY environment variable
#
# Usage:
# ruby docs/examples/query_builder.rb

require "sec_api"

# Initialize client with API key from environment
client = SecApi::Client.new(
  api_key: ENV.fetch("SECAPI_API_KEY")
)

# =============================================================================
# SECTION 1: Basic Ticker Queries
# =============================================================================

puts "=" * 60
puts "SECTION 1: Basic Ticker Queries"
puts "=" * 60

# Single ticker query - returns most recent filings for Apple
filings = client.query.ticker("AAPL").search
puts "\nApple filings: #{filings.count} total"
puts "First filing: #{filings.first.form_type} filed on #{filings.first.filed_at}" if filings.any?

# Multiple tickers - query filings for multiple companies at once
filings = client.query.ticker("AAPL", "TSLA", "GOOGL").search
puts "\nMultiple tickers: #{filings.count} total filings"

# Tickers can also be passed as an array
tickers = %w[MSFT AMZN META]
filings = client.query.ticker(*tickers).search
puts "Tech companies: #{filings.count} total filings"

# =============================================================================
# SECTION 2: CIK Queries
# =============================================================================

puts "\n" + "=" * 60
puts "SECTION 2: CIK Queries"
puts "=" * 60

# CIK with leading zeros (automatically normalized)
# Apple's CIK is 0000320193
filings = client.query.cik("0000320193").search
puts "\nApple by CIK (with zeros): #{filings.count} filings"

# CIK without leading zeros (also works)
filings = client.query.cik("320193").search
puts "Apple by CIK (without zeros): #{filings.count} filings"

# =============================================================================
# SECTION 3: Form Type Filtering
# =============================================================================

puts "\n" + "=" * 60
puts "SECTION 3: Form Type Filtering"
puts "=" * 60

# Single form type - Annual reports only
filings = client.query.ticker("AAPL").form_type("10-K").search
puts "\nApple 10-K filings: #{filings.count}"

# Multiple form types - Annual and quarterly reports
filings = client.query.ticker("AAPL").form_type("10-K", "10-Q").search
puts "Apple 10-K and 10-Q filings: #{filings.count}"

# Common SEC forms
# - 10-K: Annual report
# - 10-Q: Quarterly report
# - 8-K: Current report (material events)
# - 4: Insider trading
# - 13F: Institutional holdings
# - DEF 14A: Proxy statement

# Material events (8-K filings)
filings = client.query.ticker("TSLA").form_type("8-K").search
puts "Tesla 8-K filings: #{filings.count}"

# International form types - Foreign private issuers
# - 20-F: Foreign annual report (like 10-K for non-US companies)
# - 40-F: Canadian annual report (MJDS program)
# - 6-K: Foreign current report (like 8-K for non-US companies)

# Example: Nomura Holdings (Japanese company)
filings = client.query.ticker("NMR").form_type("20-F").search
puts "Nomura 20-F filings: #{filings.count}"

# Example: Barrick Gold (Canadian company)
filings = client.query.ticker("ABX").form_type("40-F").search
puts "Barrick 40-F filings: #{filings.count}"

# Mix domestic and international annual reports
filings = client.query.form_type("10-K", "20-F", "40-F").limit(100).search
puts "All annual reports (10-K, 20-F, 40-F): #{filings.count}"

# =============================================================================
# SECTION 4: Date Range Filtering
# =============================================================================

puts "\n" + "=" * 60
puts "SECTION 4: Date Range Filtering"
puts "=" * 60

# Using string dates (ISO 8601 format: YYYY-MM-DD)
filings = client.query
  .ticker("AAPL")
  .date_range(from: "2023-01-01", to: "2023-12-31")
  .search
puts "\nApple 2023 filings: #{filings.count}"

# Using Date objects
require "date"
filings = client.query
  .ticker("AAPL")
  .date_range(from: Date.new(2022, 1, 1), to: Date.new(2022, 12, 31))
  .search
puts "Apple 2022 filings: #{filings.count}"

# Using Time objects (time portion is ignored, uses date only)
filings = client.query
  .ticker("AAPL")
  .date_range(from: Time.now - (365 * 24 * 60 * 60), to: Time.now)
  .search
puts "Apple filings in last year: #{filings.count}"

# Using Date.today for dynamic queries
filings = client.query
  .ticker("AAPL")
  .form_type("10-Q")
  .date_range(from: Date.today - 365, to: Date.today)
  .search
puts "Apple quarterly reports in last year: #{filings.count}"

# =============================================================================
# SECTION 5: Full-Text Search
# =============================================================================

puts "\n" + "=" * 60
puts "SECTION 5: Full-Text Search"
puts "=" * 60

# Search for specific keywords in filing content
filings = client.query.search_text("merger acquisition").search
puts "\nFilings mentioning 'merger acquisition': #{filings.count}"

# Combined with ticker filter
filings = client.query
  .ticker("AAPL")
  .form_type("8-K")
  .search_text("acquisition")
  .search
puts "Apple 8-K filings mentioning 'acquisition': #{filings.count}"

# Search for specific company mentions across all filings
filings = client.query
  .search_text("artificial intelligence")
  .form_type("10-K")
  .limit(50)
  .search
puts "10-K filings mentioning 'artificial intelligence': #{filings.count}"

# =============================================================================
# SECTION 6: Combining Multiple Filters
# =============================================================================

puts "\n" + "=" * 60
puts "SECTION 6: Combining Multiple Filters"
puts "=" * 60

# Complex query: Apple's annual reports from 2020-2023
filings = client.query
  .ticker("AAPL")
  .form_type("10-K")
  .date_range(from: "2020-01-01", to: "2023-12-31")
  .search
puts "\nApple 10-K filings 2020-2023: #{filings.count}"

# All major tech companies, annual reports, recent years
filings = client.query
  .ticker("AAPL", "MSFT", "GOOGL", "AMZN", "META")
  .form_type("10-K", "10-Q")
  .date_range(from: "2022-01-01", to: Date.today.to_s)
  .search
puts "Big Tech quarterly/annual reports since 2022: #{filings.count}"

# International + domestic, with search, limited results
filings = client.query
  .form_type("10-K", "20-F")
  .search_text("climate risk")
  .date_range(from: "2023-01-01", to: "2023-12-31")
  .limit(100)
  .search
puts "Annual reports mentioning 'climate risk' in 2023: #{filings.count}"

# =============================================================================
# SECTION 7: Limiting Results
# =============================================================================

puts "\n" + "=" * 60
puts "SECTION 7: Limiting Results"
puts "=" * 60

# Default is 50 results per page
filings = client.query.ticker("AAPL").search
puts "\nDefault limit (50): #{filings.to_a.size} filings returned"

# Custom limit - get exactly what you need
filings = client.query.ticker("AAPL").limit(10).search
puts "Limited to 10: #{filings.to_a.size} filings returned"

# Limit 1 - get just the most recent filing
filing = client.query
  .ticker("TSLA")
  .form_type("10-K")
  .limit(1)
  .search
  .first
puts "Tesla's latest 10-K: #{filing.filed_at}" if filing

# =============================================================================
# SECTION 8: Manual Pagination with fetch_next_page
# =============================================================================

puts "\n" + "=" * 60
puts "SECTION 8: Manual Pagination"
puts "=" * 60

# First page of results
filings = client.query
  .ticker("AAPL")
  .form_type("10-K", "10-Q", "8-K")
  .limit(10)
  .search

puts "\nPage 1: #{filings.to_a.size} filings (total: #{filings.count})"
puts "Has more pages? #{filings.has_more?}"

# Fetch subsequent pages manually
page_number = 1
while filings.has_more? && page_number < 3  # Limit to 3 pages for demo
  filings = filings.fetch_next_page
  page_number += 1
  puts "Page #{page_number}: #{filings.to_a.size} filings"
end

# =============================================================================
# SECTION 9: Working with Filing Objects
# =============================================================================

puts "\n" + "=" * 60
puts "SECTION 9: Working with Filing Objects"
puts "=" * 60

# Get a filing and explore its attributes
filing = client.query
  .ticker("AAPL")
  .form_type("10-K")
  .limit(1)
  .search
  .first

if filing
  puts "\nFiling Details:"
  puts "  Ticker: #{filing.ticker}"
  puts "  Company: #{filing.company_name}"
  puts "  CIK: #{filing.cik}"
  puts "  Form Type: #{filing.form_type}"
  puts "  Filed At: #{filing.filed_at}"
  puts "  Accession Number: #{filing.accession_number}"
  puts "  Link to SEC: #{filing.filing_details_url}"
end

# Use Enumerable methods on the collection
filings = client.query.ticker("AAPL").limit(20).search

# Filter to specific form types
ten_ks = filings.select { |f| f.form_type == "10-K" }
puts "\nFiltered to 10-K: #{ten_ks.size} filings"

# Map to get just tickers
form_types = filings.map(&:form_type).uniq
puts "Unique form types: #{form_types.join(", ")}"

# Find first matching a condition
first_8k = filings.find { |f| f.form_type == "8-K" }
puts "First 8-K: #{first_8k.filed_at}" if first_8k

puts "\n" + "=" * 60
puts "Examples completed successfully!"
puts "=" * 60
