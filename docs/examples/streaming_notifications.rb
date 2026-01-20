#!/usr/bin/env ruby
# frozen_string_literal: true

# Example: Real-Time Streaming Notifications
#
# This example demonstrates:
# - WebSocket connection with basic subscription
# - Ticker and form type filtering
# - Callback handler with proper error isolation
# - Auto-reconnect behavior and monitoring
# - Sidekiq integration for async processing
# - Latency monitoring and alerting
# - Graceful shutdown pattern
#
# Prerequisites:
# - gem install sec_api
# - Set SECAPI_API_KEY environment variable
#
# Usage:
# ruby docs/examples/streaming_notifications.rb
#
# Note: This example demonstrates the streaming API patterns.
# Running it will connect to the SEC API WebSocket stream.
# Press Ctrl+C to stop the stream.

require "sec_api"

# =============================================================================
# SECTION 1: Basic WebSocket Subscription
# =============================================================================

puts "=" * 60
puts "SECTION 1: Basic WebSocket Subscription"
puts "=" * 60

# NOTE: These examples demonstrate the patterns.
# Uncomment the subscription calls to actually connect.

# Basic subscription - receives ALL filings
puts "\nPattern: Basic subscription (all filings)"
puts <<~CODE
  client = SecApi::Client.new
  client.stream.subscribe do |filing|
    puts "\#{filing.ticker}: \#{filing.form_type} filed at \#{filing.filed_at}"
  end
CODE

# =============================================================================
# SECTION 2: Ticker and Form Type Filtering
# =============================================================================

puts "\n" + "=" * 60
puts "SECTION 2: Ticker and Form Type Filtering"
puts "=" * 60

# Filter by ticker(s) - client-side filtering
puts "\nPattern: Filter by tickers"
puts <<~CODE
  client.stream.subscribe(tickers: ["AAPL", "TSLA", "GOOGL"]) do |filing|
    puts "Watched company: \#{filing.ticker} - \#{filing.form_type}"
  end
CODE

# Filter by form type(s) - client-side filtering
puts "\nPattern: Filter by form types"
puts <<~CODE
  # Only material events and annual/quarterly reports
  client.stream.subscribe(form_types: ["10-K", "10-Q", "8-K"]) do |filing|
    puts "Material filing: \#{filing.form_type}"
  end
CODE

# Combined filters (AND logic)
puts "\nPattern: Combined filters (ticker AND form_type)"
puts <<~CODE
  # Only 10-K and 10-Q for specific tickers
  client.stream.subscribe(
    tickers: ["AAPL", "MSFT"],
    form_types: ["10-K", "10-Q"]
  ) do |filing|
    puts "Quarterly/Annual report for \#{filing.ticker}"
    analyze_financials(filing)
  end
CODE

# Amendments are matched automatically
puts "\nPattern: Amendments matching"
puts <<~CODE
  # Filter "10-K" also matches "10-K/A" (amendments)
  client.stream.subscribe(form_types: ["10-K"]) do |filing|
    # This receives both 10-K and 10-K/A filings
    puts "\#{filing.form_type}"  # Could be "10-K" or "10-K/A"
  end
CODE

# =============================================================================
# SECTION 3: Callback Handler with Error Isolation
# =============================================================================

puts "\n" + "=" * 60
puts "SECTION 3: Error Isolation in Callbacks"
puts "=" * 60

# Errors in your callback don't crash the stream
puts "\nPattern: Error-safe callback processing"
puts <<~CODE
  client = SecApi::Client.new(
    api_key: ENV.fetch("SECAPI_API_KEY"),
    on_callback_error: ->(info) {
      # Called when your callback raises an exception
      Bugsnag.notify(info[:error], {
        accession_no: info[:accession_no],
        ticker: info[:ticker]
      })
    }
  )

  client.stream.subscribe do |filing|
    # If this raises, on_callback_error is called and stream continues
    process_filing(filing)  # May raise!
  end
CODE

# Defensive callback pattern
puts "\nPattern: Defensive callback with rescue"
puts <<~CODE
  client.stream.subscribe do |filing|
    begin
      # Your processing logic
      validate_filing(filing)
      store_filing(filing)
      trigger_alerts(filing)
    rescue StandardError => e
      # Log error but don't re-raise - stream continues
      Rails.logger.error("Filing callback failed: \#{e.message}")
      ErrorTracker.capture(e, filing: filing.to_h)
    end
  end
CODE

# =============================================================================
# SECTION 4: Auto-Reconnect Behavior and Monitoring
# =============================================================================

puts "\n" + "=" * 60
puts "SECTION 4: Auto-Reconnect and Monitoring"
puts "=" * 60

# Configure reconnection behavior
puts "\nPattern: Custom reconnection settings"
puts <<~CODE
  config = SecApi::Config.new(
    api_key: ENV.fetch("SECAPI_API_KEY"),

    # Reconnection settings
    stream_max_reconnect_attempts: 10,      # Give up after 10 attempts
    stream_initial_reconnect_delay: 1.0,    # Start with 1 second
    stream_max_reconnect_delay: 60.0,       # Cap at 1 minute
    stream_backoff_multiplier: 2,           # Exponential: 1s, 2s, 4s, 8s...

    # Called on successful reconnection
    on_reconnect: ->(info) {
      Rails.logger.info("Stream reconnected", {
        attempts: info[:attempt_count],
        downtime_seconds: info[:downtime_seconds]
      })

      # Alert if downtime was significant
      if info[:downtime_seconds] > 60
        AlertService.warn("SEC stream reconnected after \#{info[:downtime_seconds]}s downtime")
      end
    }
  )

  client = SecApi::Client.new(config)
CODE

# Backfill after reconnection
puts "\nPattern: Backfill missed filings after reconnection"
puts <<~CODE
  last_filing_time = nil
  reconnected = false

  config = SecApi::Config.new(
    api_key: ENV.fetch("SECAPI_API_KEY"),
    on_reconnect: ->(info) {
      reconnected = true
    }
  )

  client = SecApi::Client.new(config)

  client.stream.subscribe(tickers: ["AAPL"]) do |filing|
    if reconnected && last_filing_time
      # Backfill any missed filings via Query API
      missed = client.query
        .ticker("AAPL")
        .date_range(from: last_filing_time, to: Time.now)
        .search

      missed.each { |f| process_filing(f) }
      reconnected = false
    end

    last_filing_time = filing.filed_at
    process_filing(filing)
  end
CODE

# =============================================================================
# SECTION 5: Sidekiq/Background Job Integration
# =============================================================================

puts "\n" + "=" * 60
puts "SECTION 5: Background Job Integration"
puts "=" * 60

# Sidekiq integration - keep callbacks fast
puts "\nPattern: Sidekiq job enqueueing"
puts <<~CODE
  # Job class (in app/workers/process_filing_worker.rb)
  class ProcessFilingWorker
    include Sidekiq::Worker

    def perform(accession_no, ticker, form_type, filed_at)
      # Fetch full filing details if needed
      client = SecApi::Client.new
      filings = client.query
        .ticker(ticker)
        .form_type(form_type)
        .limit(1)
        .search

      filing = filings.first
      return unless filing

      # Your processing logic
      analyze_filing(filing)
      store_in_database(filing)
      send_notifications(filing)
    end
  end

  # Stream handler - just enqueue jobs, don't block
  client.stream.subscribe do |filing|
    # Enqueue and return immediately - don't block the reactor
    ProcessFilingWorker.perform_async(
      filing.accession_no,
      filing.ticker,
      filing.form_type,
      filing.filed_at.iso8601
    )
  end
CODE

# ActiveJob integration
puts "\nPattern: ActiveJob integration"
puts <<~CODE
  # Job class (in app/jobs/process_filing_job.rb)
  class ProcessFilingJob < ApplicationJob
    queue_as :sec_filings

    def perform(accession_no:, ticker:, form_type:)
      # Your processing logic here
    end
  end

  # Stream handler
  client.stream.subscribe do |filing|
    ProcessFilingJob.perform_later(
      accession_no: filing.accession_no,
      ticker: filing.ticker,
      form_type: filing.form_type
    )
  end
CODE

# Thread pool for non-Rails apps
puts "\nPattern: Thread pool processing"
puts <<~CODE
  require 'concurrent'

  pool = Concurrent::ThreadPoolExecutor.new(
    min_threads: 2,
    max_threads: 10,
    max_queue: 100
  )

  client.stream.subscribe do |filing|
    pool.post do
      process_filing(filing)
    end
  end
CODE

# =============================================================================
# SECTION 6: Latency Monitoring and Alerting
# =============================================================================

puts "\n" + "=" * 60
puts "SECTION 6: Latency Monitoring"
puts "=" * 60

# Monitor filing delivery latency
puts "\nPattern: Latency monitoring with on_filing callback"
puts <<~CODE
  config = SecApi::Config.new(
    api_key: ENV.fetch("SECAPI_API_KEY"),

    # Latency warning threshold (2 minutes = 120 seconds)
    stream_latency_warning_threshold: 120.0,

    # Called for every filing (before filtering)
    on_filing: ->(filing:, latency_ms:, received_at:) {
      # Record latency metrics
      StatsD.histogram("sec_api.stream.latency_ms", latency_ms)
      StatsD.increment("sec_api.stream.filings_received")

      # Alert on high latency
      if latency_ms > 120_000  # 2 minutes in ms
        AlertService.warn("SEC filing latency exceeded 2 minutes", {
          accession_no: filing.accession_no,
          latency_ms: latency_ms
        })
      end
    }
  )

  client = SecApi::Client.new(config)
CODE

# Access latency from filing object
puts "\nPattern: Latency from filing object"
puts <<~CODE
  client.stream.subscribe do |filing|
    puts "Filing latency: \#{filing.latency_ms}ms"
    puts "Filed at: \#{filing.filed_at}"
    puts "Received at: \#{filing.received_at}"

    # filing.latency_seconds is also available
    if filing.latency_seconds > 60
      puts "Warning: High latency (\#{filing.latency_seconds}s)"
    end
  end
CODE

# Structured logging for latency
puts "\nPattern: Structured latency logging"
puts <<~CODE
  config = SecApi::Config.new(
    api_key: ENV.fetch("SECAPI_API_KEY"),
    logger: Rails.logger,
    log_level: :info  # Logs JSON events automatically
  )

  # With logger configured, the stream automatically logs:
  # {"event":"secapi.stream.filing_received","latency_ms":1500,...}
  # {"event":"secapi.stream.latency_warning","latency_ms":130000,...}
CODE

# =============================================================================
# SECTION 7: Graceful Shutdown Pattern
# =============================================================================

puts "\n" + "=" * 60
puts "SECTION 7: Graceful Shutdown"
puts "=" * 60

# Clean shutdown with signal handling
puts "\nPattern: Signal-based graceful shutdown"
puts <<~CODE
  client = SecApi::Client.new
  stream = client.stream

  # Handle shutdown signals
  shutdown = false

  %w[INT TERM].each do |signal|
    Signal.trap(signal) do
      puts "\\nReceived \#{signal}, shutting down..."
      shutdown = true
      stream.close  # Close the WebSocket connection
    end
  end

  # Start streaming in a way that respects shutdown
  Thread.new do
    stream.subscribe do |filing|
      break if shutdown
      process_filing(filing)
    end
  rescue SecApi::NetworkError => e
    # Connection closed or network error
    puts "Stream disconnected: \#{e.message}" unless shutdown
  end.join
CODE

# Check connection status
puts "\nPattern: Connection status monitoring"
puts <<~CODE
  stream = client.stream

  # Start streaming in background
  streaming_thread = Thread.new do
    stream.subscribe(tickers: ["AAPL"]) { |f| process(f) }
  end

  # Monitor connection status from main thread
  loop do
    if stream.connected?
      puts "Stream connected, filters: \#{stream.filters}"
    else
      puts "Stream disconnected"
    end
    sleep 30
  end
CODE

# =============================================================================
# SECTION 8: Complete Example
# =============================================================================

puts "\n" + "=" * 60
puts "SECTION 8: Complete Production Example"
puts "=" * 60

puts "\nComplete production-ready streaming setup:"
puts <<~CODE
  require "sec_api"

  # Configure with all observability features
  config = SecApi::Config.new(
    api_key: ENV.fetch("SECAPI_API_KEY"),

    # Logging
    logger: Rails.logger,
    log_level: :info,

    # Latency monitoring
    stream_latency_warning_threshold: 120.0,

    # Reconnection
    stream_max_reconnect_attempts: 10,
    stream_initial_reconnect_delay: 1.0,
    stream_max_reconnect_delay: 60.0,

    # Callbacks for observability
    on_filing: ->(filing:, latency_ms:, received_at:) {
      StatsD.histogram("sec_api.stream.latency_ms", latency_ms)
    },

    on_reconnect: ->(info) {
      StatsD.increment("sec_api.stream.reconnected")
      StatsD.gauge("sec_api.stream.downtime_seconds", info[:downtime_seconds])
    },

    on_callback_error: ->(info) {
      Bugsnag.notify(info[:error], {
        accession_no: info[:accession_no],
        ticker: info[:ticker]
      })
    }
  )

  client = SecApi::Client.new(config)

  # Track for backfill detection
  last_received = nil

  # Subscribe with filtering
  client.stream.subscribe(
    tickers: %w[AAPL TSLA MSFT GOOGL AMZN],
    form_types: %w[10-K 10-Q 8-K]
  ) do |filing|
    last_received = Time.now

    # Enqueue for background processing
    ProcessFilingWorker.perform_async(
      filing.accession_no,
      filing.ticker,
      filing.form_type,
      filing.filed_at.iso8601
    )
  end
CODE

puts "\n" + "=" * 60
puts "Examples completed!"
puts "=" * 60
puts "\nNote: These examples demonstrate patterns."
puts "Uncomment the code blocks to run them with a live connection."
