#!/usr/bin/env ruby
# frozen_string_literal: true

# Example: Backfill Historical Filings
#
# This example demonstrates:
# - Multi-year backfill using auto_paginate
# - Progress logging with processed count and estimated completion
# - Error handling with TransientError/PermanentError distinction
# - Memory-efficient lazy enumeration pattern
# - Storing/processing filings during iteration
# - Sidekiq/background job integration pattern
# - Rate limit handling best practices
#
# Prerequisites:
# - gem install sec_api
# - Set SECAPI_API_KEY environment variable
#
# Usage:
# ruby docs/examples/backfill_filings.rb

require "sec_api"

# Initialize client with API key from environment
client = SecApi::Client.new(
  api_key: ENV.fetch("SECAPI_API_KEY")
)

# =============================================================================
# SECTION 1: Basic Auto-Pagination
# =============================================================================

puts "=" * 60
puts "SECTION 1: Basic Auto-Pagination"
puts "=" * 60

# auto_paginate returns a lazy enumerator that fetches pages on-demand
# Memory efficient: only one page is held in memory at a time
filings = client.query
  .ticker("AAPL")
  .form_type("10-K", "10-Q")
  .date_range(from: "2020-01-01", to: Date.today.to_s)
  .auto_paginate

# Process each filing - pages are fetched automatically as needed
count = 0
filings.each do |filing|
  puts "  #{filing.filed_at}: #{filing.form_type} - #{filing.company_name}"
  count += 1
  break if count >= 5  # Early termination works with lazy enumerators
end
puts "Processed #{count} filings (limited to 5 for demo)"

# =============================================================================
# SECTION 2: Multi-Year Backfill with Progress Logging
# =============================================================================

puts "\n" + "=" * 60
puts "SECTION 2: Multi-Year Backfill with Progress"
puts "=" * 60

# Define the backfill parameters
ticker = "TSLA"
form_types = %w[10-K 10-Q 8-K]
start_date = Date.new(2020, 1, 1)
end_date = Date.today

# First, get the total count to estimate completion
initial_results = client.query
  .ticker(ticker)
  .form_type(*form_types)
  .date_range(from: start_date.to_s, to: end_date.to_s)
  .limit(1)
  .search

total_count = initial_results.count
puts "\nBackfilling #{total_count} #{ticker} filings from #{start_date} to #{end_date}"
puts "Form types: #{form_types.join(", ")}"
puts "-" * 40

# Now iterate with progress tracking
processed = 0
start_time = Time.now

client.query
  .ticker(ticker)
  .form_type(*form_types)
  .date_range(from: start_date.to_s, to: end_date.to_s)
  .auto_paginate
  .each do |filing|
    processed += 1

    # Calculate progress metrics
    elapsed_seconds = Time.now - start_time
    rate = processed / [elapsed_seconds, 1].max
    remaining = total_count - processed
    eta_seconds = remaining / [rate, 0.1].max

    # Log progress every 10 filings
    if (processed % 10).zero? || processed == total_count
      progress_pct = (processed.to_f / total_count * 100).round(1)
      eta_minutes = (eta_seconds / 60).round(1)

      puts "[#{progress_pct}%] Processed #{processed}/#{total_count} - " \
           "Rate: #{rate.round(1)}/sec - ETA: #{eta_minutes} min"
    end

    # Simulate processing (replace with your actual logic)
    # store_filing(filing)

    # Early termination for demo
    break if processed >= 30
  end

puts "\nBackfill complete: #{processed} filings processed in #{(Time.now - start_time).round(1)} seconds"

# =============================================================================
# SECTION 3: Error Handling with TransientError/PermanentError
# =============================================================================

puts "\n" + "=" * 60
puts "SECTION 3: Error Handling"
puts "=" * 60

# The gem automatically retries TransientErrors (network issues, 5xx errors, rate limits)
# PermanentErrors (invalid API key, 404s) are raised immediately

# Example: Backfill with comprehensive error handling
def backfill_with_error_handling(client, ticker:, form_types:, start_date:, end_date:)
  processed = 0
  errors = []

  begin
    client.query
      .ticker(ticker)
      .form_type(*form_types)
      .date_range(from: start_date.to_s, to: end_date.to_s)
      .auto_paginate
      .each do |filing|
        # Process the filing
        process_filing(filing)
        processed += 1
      rescue => e
        # Log individual filing processing errors but continue
        errors << {accession_no: filing.accession_number, error: e.message}
        puts "  Warning: Failed to process #{filing.accession_number}: #{e.message}"
      end
  rescue SecApi::AuthenticationError => e
    # Invalid API key - unrecoverable
    puts "ERROR: Authentication failed - check your API key"
    puts "  #{e.message}"
    raise
  rescue SecApi::RateLimitError => e
    # All retries exhausted - consider increasing retry_max_attempts
    puts "ERROR: Rate limit exceeded after all retries"
    puts "  Retry after: #{e.retry_after} seconds" if e.retry_after
    puts "  Reset at: #{e.reset_at}" if e.reset_at
    raise
  rescue SecApi::NetworkError => e
    # Network issues persisted after all retries
    puts "ERROR: Network error after all retries"
    puts "  #{e.message}"
    raise
  rescue SecApi::ServerError => e
    # SEC API server issues persisted after all retries
    puts "ERROR: Server error after all retries"
    puts "  #{e.message}"
    raise
  rescue SecApi::PaginationError => e
    # Pagination state error - should not happen normally
    puts "ERROR: Pagination error"
    puts "  #{e.message}"
    raise
  end

  {processed: processed, errors: errors}
end

# Helper method for processing filings
def process_filing(filing)
  # Your processing logic here
  # Examples:
  # - Store in database
  # - Extract XBRL data
  # - Send to analytics pipeline
end

# Demo the error handling (will succeed normally)
puts "\nRunning backfill with error handling..."
result = backfill_with_error_handling(
  client,
  ticker: "MSFT",
  form_types: %w[10-K],
  start_date: Date.new(2022, 1, 1),
  end_date: Date.new(2023, 12, 31)
)
puts "Result: #{result[:processed]} processed, #{result[:errors].size} errors"

# =============================================================================
# SECTION 4: Memory-Efficient Lazy Enumeration
# =============================================================================

puts "\n" + "=" * 60
puts "SECTION 4: Memory-Efficient Processing"
puts "=" * 60

# auto_paginate uses lazy evaluation - memory usage stays constant
# regardless of total result count

# BAD: Collects all results into memory (avoid for large datasets!)
# all_filings = client.query.ticker("AAPL").auto_paginate.to_a

# GOOD: Process one filing at a time - only current page in memory
puts "\nProcessing with lazy enumeration (constant memory):"
client.query
  .ticker("GOOGL")
  .form_type("10-K", "10-Q")
  .date_range(from: "2020-01-01", to: Date.today.to_s)
  .auto_paginate
  .each_with_index do |filing, index|
    # Each filing is processed and can be garbage collected
    # Only the current page (~50 filings) is in memory
    puts "  [#{index + 1}] #{filing.filed_at}: #{filing.form_type}"
    break if index >= 4
  end

# Use Enumerable methods that preserve laziness
puts "\nLazy filtering (no extra memory):"
ten_k_filings = client.query
  .ticker("AMZN")
  .date_range(from: "2020-01-01", to: Date.today.to_s)
  .auto_paginate
  .select { |f| f.form_type == "10-K" }  # Lazy filter
  .take(3)                                # Lazy limit

ten_k_filings.each do |filing|
  puts "  #{filing.filed_at}: #{filing.form_type}"
end

# =============================================================================
# SECTION 5: Storing/Processing During Iteration
# =============================================================================

puts "\n" + "=" * 60
puts "SECTION 5: Processing Patterns"
puts "=" * 60

# Pattern 1: Batch processing (group filings before processing)
puts "\nPattern 1: Batch processing"
batch = []
batch_size = 10

client.query
  .ticker("META")
  .form_type("8-K")
  .date_range(from: "2023-01-01", to: Date.today.to_s)
  .auto_paginate
  .each do |filing|
    batch << filing

    if batch.size >= batch_size
      # Process batch
      puts "  Processing batch of #{batch.size} filings..."
      # bulk_insert(batch)
      batch.clear
    end
  end

# Don't forget the remaining filings
if batch.any?
  puts "  Processing final batch of #{batch.size} filings..."
  # bulk_insert(batch)
end

# Pattern 2: Transform and collect specific data
puts "\nPattern 2: Transform and collect"
filing_summaries = client.query
  .ticker("NFLX")
  .form_type("10-K")
  .date_range(from: "2018-01-01", to: Date.today.to_s)
  .auto_paginate
  .map do |filing|
    {
      year: filing.filed_at.year,
      form: filing.form_type,
      accession: filing.accession_number
    }
  end
  .to_a  # Materialize only the summary data, not full Filing objects

puts "  Collected #{filing_summaries.size} filing summaries"
filing_summaries.first(3).each { |s| puts "    #{s}" }

# Pattern 3: Reduce/aggregate across all filings
puts "\nPattern 3: Aggregate/reduce"
form_type_counts = client.query
  .ticker("AAPL")
  .date_range(from: "2022-01-01", to: Date.today.to_s)
  .auto_paginate
  .each_with_object(Hash.new(0)) do |filing, counts|
    counts[filing.form_type] += 1
  end

puts "  Form type distribution:"
form_type_counts.sort_by { |_, count| -count }.first(5).each do |form_type, count|
  puts "    #{form_type}: #{count}"
end

# =============================================================================
# SECTION 6: Sidekiq/Background Job Integration
# =============================================================================

puts "\n" + "=" * 60
puts "SECTION 6: Background Job Integration"
puts "=" * 60

# This section demonstrates patterns for integrating with Sidekiq or other
# background job systems.

# Pattern: Enqueue jobs for each filing
# class ProcessFilingJob
#   include Sidekiq::Job
#
#   def perform(accession_no, ticker, form_type, filed_at)
#     # Your processing logic here
#     client = SecApi::Client.new
#     # ... process the filing ...
#   end
# end

puts "\nSimulating Sidekiq job enqueueing:"
job_count = 0

client.query
  .ticker("NVDA")
  .form_type("10-K", "10-Q")
  .date_range(from: "2022-01-01", to: Date.today.to_s)
  .auto_paginate
  .each do |filing|
    # Enqueue a background job for each filing
    # ProcessFilingJob.perform_async(
    #   filing.accession_number,
    #   filing.ticker,
    #   filing.form_type,
    #   filing.filed_at.iso8601
    # )

    puts "  Enqueued: #{filing.accession_number} (#{filing.form_type})"
    job_count += 1
    break if job_count >= 5
  end

puts "Enqueued #{job_count} jobs (limited for demo)"

# =============================================================================
# SECTION 7: Rate Limit Handling Best Practices
# =============================================================================

puts "\n" + "=" * 60
puts "SECTION 7: Rate Limit Best Practices"
puts "=" * 60

# Configure client with rate limit callbacks for visibility
config = SecApi::Config.new(
  api_key: ENV.fetch("SECAPI_API_KEY"),

  # Proactive throttling: slow down before hitting the limit
  rate_limit_threshold: 0.2,  # Throttle at 20% remaining

  # Callback when proactive throttling occurs
  on_throttle: ->(info) {
    puts "  [Throttle] Remaining: #{info[:remaining]}/#{info[:limit]}, " \
         "delay: #{info[:delay].round(1)}s"
  },

  # Callback when 429 rate limit is hit (and being retried)
  on_rate_limit: ->(info) {
    puts "  [429 Hit] Retry after: #{info[:retry_after]}s, attempt: #{info[:attempt]}"
  },

  # Callback when requests are queued (rate limit exhausted)
  on_queue: ->(info) {
    puts "  [Queued] Queue size: #{info[:queue_size]}, wait: #{info[:wait_time].round(1)}s"
  }
)

rate_aware_client = SecApi::Client.new(config)

puts "\nMonitoring rate limits during backfill:"
puts "Rate limit threshold: 20% (will throttle when < 20% remaining)"
puts "-" * 40

# The client will automatically:
# 1. Track rate limit headers from each response
# 2. Proactively throttle when approaching the limit
# 3. Queue requests when limit is exhausted
# 4. Automatically retry 429 responses with exponential backoff

processed = 0
rate_aware_client.query
  .ticker("AMD")
  .form_type("10-K", "10-Q", "8-K")
  .date_range(from: "2022-01-01", to: Date.today.to_s)
  .auto_paginate
  .each do |filing|
    processed += 1
    break if processed >= 10
  end

# Check rate limit status after processing
summary = rate_aware_client.rate_limit_summary
puts "\nRate limit status after processing:"
puts "  Remaining: #{summary[:remaining]}/#{summary[:limit]} (#{summary[:percentage]&.round(1)}%)"
puts "  Queued requests: #{summary[:queued_count]}"
puts "  Exhausted: #{summary[:exhausted]}"

puts "\n" + "=" * 60
puts "Examples completed successfully!"
puts "=" * 60
