#!/usr/bin/env ruby
# frozen_string_literal: true

# Example: Instrumentation and Observability
#
# This example demonstrates:
# - All callback hooks (on_request, on_response, on_retry, on_error, on_rate_limit)
# - Integration with Rails.logger for structured logging
# - Integration with StatsD/Datadog for metrics
# - Bugsnag/Sentry error tracking integration
# - Correlation ID usage for request tracing
# - Filing journey tracking
# - metrics_backend configuration pattern
#
# Prerequisites:
# - gem install sec_api
# - Set SECAPI_API_KEY environment variable
#
# Usage:
# ruby docs/examples/instrumentation.rb

require "sec_api"
require "logger"

# =============================================================================
# SECTION 1: All Callback Hooks Overview
# =============================================================================

puts "=" * 60
puts "SECTION 1: Callback Hooks Overview"
puts "=" * 60

# The SecApi client provides these instrumentation callbacks:
# - on_request: Called BEFORE each REST API request
# - on_response: Called AFTER each REST API response
# - on_retry: Called BEFORE each retry attempt (transient errors)
# - on_error: Called on FINAL failure (after all retries exhausted)
# - on_rate_limit: Called when 429 rate limit is hit
# - on_throttle: Called when proactive throttling occurs
# - on_queue: Called when a request is queued (rate limit exhausted)
# - on_dequeue: Called when a request exits the queue
# - on_filing: Called for each filing received via stream
# - on_reconnect: Called when WebSocket reconnects after disconnect
# - on_callback_error: Called when a stream callback raises an error

puts "\nCallback hooks available:"
puts "  REST API: on_request, on_response, on_retry, on_error"
puts "  Rate Limiting: on_rate_limit, on_throttle, on_queue, on_dequeue"
puts "  Streaming: on_filing, on_reconnect, on_callback_error"

# =============================================================================
# SECTION 2: Basic Callback Configuration
# =============================================================================

puts "\n" + "=" * 60
puts "SECTION 2: Basic Callback Configuration"
puts "=" * 60

# Create a simple logger for demonstration
demo_logger = Logger.new($stdout)
demo_logger.formatter = proc { |sev, time, prog, msg| "#{sev}: #{msg}\n" }

# Configure all callbacks
config = SecApi::Config.new(
  api_key: ENV.fetch("SECAPI_API_KEY"),

  # Request lifecycle callbacks
  on_request: ->(request_id:, method:, url:, headers:) {
    demo_logger.info("[REQUEST] #{request_id} #{method.upcase} #{url}")
  },

  on_response: ->(request_id:, status:, duration_ms:, url:, method:) {
    demo_logger.info("[RESPONSE] #{request_id} #{status} in #{duration_ms}ms")
  },

  on_retry: ->(request_id:, attempt:, max_attempts:, error_class:, error_message:, will_retry_in:) {
    demo_logger.warn("[RETRY] #{request_id} attempt #{attempt}/#{max_attempts} " \
                     "due to #{error_class}, retry in #{will_retry_in}s")
  },

  on_error: ->(request_id:, error:, url:, method:) {
    demo_logger.error("[ERROR] #{request_id} #{error.class}: #{error.message}")
  }
)

client = SecApi::Client.new(config)

# Make a request to see the callbacks in action
puts "\nMaking a test request with callbacks:"
filings = client.query.ticker("AAPL").limit(1).search
puts "Received #{filings.count} filings"

# =============================================================================
# SECTION 3: Structured Logging with Rails.logger
# =============================================================================

puts "\n" + "=" * 60
puts "SECTION 3: Structured Logging"
puts "=" * 60

# Pattern 1: Using default_logging for automatic structured logging
puts "\nPattern 1: Automatic structured logging"
puts <<~CODE
  config = SecApi::Config.new(
    api_key: ENV.fetch("SECAPI_API_KEY"),
    logger: Rails.logger,
    log_level: :info,
    default_logging: true  # Enable automatic structured logging
  )

  client = SecApi::Client.new(config)

  # Logs are automatically generated as JSON:
  # {"event":"secapi.request.start","request_id":"abc-123","method":"GET",...}
  # {"event":"secapi.request.complete","request_id":"abc-123","status":200,...}
CODE

# Pattern 2: Manual structured logging with StructuredLogger
puts "\nPattern 2: Manual StructuredLogger usage"
puts <<~CODE
  # Use StructuredLogger directly for custom logging
  SecApi::StructuredLogger.log_request(Rails.logger, :info,
    request_id: "abc-123",
    method: :get,
    url: "https://api.sec-api.io/query"
  )

  SecApi::StructuredLogger.log_response(Rails.logger, :info,
    request_id: "abc-123",
    status: 200,
    duration_ms: 150,
    url: "https://api.sec-api.io/query",
    method: :get
  )

  SecApi::StructuredLogger.log_retry(Rails.logger, :warn,
    request_id: "abc-123",
    attempt: 2,
    max_attempts: 5,
    error_class: "SecApi::ServerError",
    error_message: "Internal Server Error",
    will_retry_in: 4.0
  )

  SecApi::StructuredLogger.log_error(Rails.logger, :error,
    request_id: "abc-123",
    error: SecApi::NetworkError.new("Connection refused"),
    url: "https://api.sec-api.io/query",
    method: :get
  )
CODE

# Demonstrate actual structured logging
puts "\nActual structured log output:"
json_logger = Logger.new($stdout)
json_logger.formatter = proc { |sev, time, prog, msg| "#{msg}\n" }

SecApi::StructuredLogger.log_request(json_logger, :info,
  request_id: "demo-request-123",
  method: :post,
  url: "https://api.sec-api.io/query")

SecApi::StructuredLogger.log_response(json_logger, :info,
  request_id: "demo-request-123",
  status: 200,
  duration_ms: 142,
  url: "https://api.sec-api.io/query",
  method: :post)

# =============================================================================
# SECTION 4: StatsD/Datadog Metrics Integration
# =============================================================================

puts "\n" + "=" * 60
puts "SECTION 4: Metrics Integration (StatsD/Datadog)"
puts "=" * 60

# Pattern 1: Using metrics_backend for automatic metrics collection
puts "\nPattern 1: Automatic metrics with metrics_backend"
puts <<~CODE
  require 'statsd-ruby'  # or 'datadog/statsd'

  statsd = StatsD.new('localhost', 8125)

  config = SecApi::Config.new(
    api_key: ENV.fetch("SECAPI_API_KEY"),
    metrics_backend: statsd  # Enables automatic metrics collection
  )

  client = SecApi::Client.new(config)

  # Metrics are automatically collected:
  # sec_api.requests.total (counter)
  # sec_api.requests.duration_ms (histogram)
  # sec_api.requests.success / sec_api.requests.error (counters)
  # sec_api.retries.total (counter)
  # sec_api.rate_limit.throttle (counter)
  # sec_api.rate_limit.exceeded (counter)
  # sec_api.stream.filings_received (counter)
  # sec_api.stream.latency_ms (histogram)
CODE

# Pattern 2: Manual StatsD integration via callbacks
puts "\nPattern 2: Manual StatsD via callbacks"
puts <<~CODE
  require 'statsd-ruby'
  statsd = StatsD.new('localhost', 8125)

  config = SecApi::Config.new(
    api_key: ENV.fetch("SECAPI_API_KEY"),

    on_response: ->(request_id:, status:, duration_ms:, url:, method:) {
      # Histogram for request duration
      statsd.histogram("sec_api.request.duration_ms", duration_ms)

      # Counter for success/error by status
      if status >= 400
        statsd.increment("sec_api.request.error", tags: ["status:\#{status}"])
      else
        statsd.increment("sec_api.request.success")
      end
    },

    on_retry: ->(request_id:, attempt:, max_attempts:, error_class:, **) {
      statsd.increment("sec_api.retry", tags: [
        "attempt:\#{attempt}",
        "error:\#{error_class}"
      ])
    },

    on_rate_limit: ->(info) {
      statsd.increment("sec_api.rate_limit.exceeded")
      statsd.gauge("sec_api.rate_limit.retry_after", info[:retry_after] || 0)
    },

    on_throttle: ->(info) {
      statsd.increment("sec_api.rate_limit.throttle")
      statsd.histogram("sec_api.rate_limit.delay", info[:delay])
      statsd.gauge("sec_api.rate_limit.remaining", info[:remaining])
    }
  )
CODE

# Pattern 3: Datadog with tags
puts "\nPattern 3: Datadog StatsD with tags"
puts <<~CODE
  require 'datadog/statsd'
  statsd = Datadog::Statsd.new('localhost', 8125)

  config = SecApi::Config.new(
    api_key: ENV.fetch("SECAPI_API_KEY"),

    on_response: ->(request_id:, status:, duration_ms:, url:, method:) {
      tags = [
        "method:\#{method}",
        "status:\#{status}",
        "status_class:\#{status / 100}xx"
      ]

      statsd.histogram("sec_api.request.duration", duration_ms, tags: tags)
      statsd.increment("sec_api.request.total", tags: tags)
    }
  )
CODE

# =============================================================================
# SECTION 5: Error Tracking (Bugsnag/Sentry)
# =============================================================================

puts "\n" + "=" * 60
puts "SECTION 5: Error Tracking Integration"
puts "=" * 60

# Pattern 1: Bugsnag integration
puts "\nPattern 1: Bugsnag integration"
puts <<~CODE
  config = SecApi::Config.new(
    api_key: ENV.fetch("SECAPI_API_KEY"),

    on_error: ->(request_id:, error:, url:, method:) {
      Bugsnag.notify(error) do |report|
        report.add_metadata(:sec_api, {
          request_id: request_id,
          url: url,
          method: method
        })

        # Set severity based on error type
        if error.is_a?(SecApi::PermanentError)
          report.severity = "error"
        else
          report.severity = "warning"  # Transient errors that exhausted retries
        end
      end
    },

    # Also track stream callback errors
    on_callback_error: ->(info) {
      Bugsnag.notify(info[:error]) do |report|
        report.add_metadata(:filing, {
          accession_no: info[:accession_no],
          ticker: info[:ticker]
        })
      end
    }
  )
CODE

# Pattern 2: Sentry integration
puts "\nPattern 2: Sentry integration"
puts <<~CODE
  config = SecApi::Config.new(
    api_key: ENV.fetch("SECAPI_API_KEY"),

    on_error: ->(request_id:, error:, url:, method:) {
      Sentry.capture_exception(error) do |scope|
        scope.set_tags(
          sec_api_request_id: request_id,
          sec_api_method: method
        )
        scope.set_context("sec_api", {
          url: url,
          error_class: error.class.name
        })
      end
    }
  )
CODE

# =============================================================================
# SECTION 6: Correlation ID Usage for Request Tracing
# =============================================================================

puts "\n" + "=" * 60
puts "SECTION 6: Correlation ID Tracing"
puts "=" * 60

puts "\nThe request_id parameter is a UUID generated per request."
puts "Use it to correlate logs, metrics, and errors for a single request."

# Pattern: Full request tracing
puts "\nPattern: Full request lifecycle tracing"
puts <<~CODE
  config = SecApi::Config.new(
    api_key: ENV.fetch("SECAPI_API_KEY"),
    logger: Rails.logger,

    on_request: ->(request_id:, method:, url:, headers:) {
      # Store request_id in thread-local for access elsewhere
      Thread.current[:sec_api_request_id] = request_id

      Rails.logger.info("[SEC_API] Request started", {
        request_id: request_id,
        method: method,
        url: url
      })
    },

    on_response: ->(request_id:, status:, duration_ms:, url:, method:) {
      Rails.logger.info("[SEC_API] Request completed", {
        request_id: request_id,
        status: status,
        duration_ms: duration_ms
      })

      Thread.current[:sec_api_request_id] = nil
    },

    on_retry: ->(request_id:, attempt:, max_attempts:, error_class:, **) {
      Rails.logger.warn("[SEC_API] Retrying", {
        request_id: request_id,
        attempt: attempt,
        max_attempts: max_attempts,
        error_class: error_class
      })
    },

    on_error: ->(request_id:, error:, url:, method:) {
      Rails.logger.error("[SEC_API] Request failed", {
        request_id: request_id,
        error_class: error.class.name,
        error_message: error.message
      })

      Thread.current[:sec_api_request_id] = nil
    }
  )
CODE

# Pattern: OpenTelemetry integration
puts "\nPattern: OpenTelemetry tracing"
puts <<~CODE
  config = SecApi::Config.new(
    api_key: ENV.fetch("SECAPI_API_KEY"),

    on_request: ->(request_id:, method:, url:, headers:) {
      span = OpenTelemetry::Trace.current_span
      span.set_attribute("sec_api.request_id", request_id)
      span.set_attribute("http.method", method.to_s.upcase)
      span.set_attribute("http.url", url)
    },

    on_response: ->(request_id:, status:, duration_ms:, url:, method:) {
      span = OpenTelemetry::Trace.current_span
      span.set_attribute("http.status_code", status)
      span.set_attribute("sec_api.duration_ms", duration_ms)
    }
  )
CODE

# =============================================================================
# SECTION 7: Filing Journey Tracking
# =============================================================================

puts "\n" + "=" * 60
puts "SECTION 7: Filing Journey Tracking"
puts "=" * 60

puts "\nFilingJourney tracks a filing through your processing pipeline:"
puts "  detected -> queried -> extracted -> processed"
puts "\nUse accession_no as the correlation key across all stages."

# Demonstrate FilingJourney logging
puts "\nFilingJourney log output:"
journey_logger = Logger.new($stdout)
journey_logger.formatter = proc { |sev, time, prog, msg| "#{msg}\n" }

SecApi::FilingJourney.log_detected(journey_logger, :info,
  accession_no: "0000320193-24-000001",
  ticker: "AAPL",
  form_type: "10-K",
  latency_ms: 1500)

SecApi::FilingJourney.log_queried(journey_logger, :info,
  accession_no: "0000320193-24-000001",
  found: true,
  duration_ms: 150)

SecApi::FilingJourney.log_extracted(journey_logger, :info,
  accession_no: "0000320193-24-000001",
  facts_count: 42,
  duration_ms: 200)

SecApi::FilingJourney.log_processed(journey_logger, :info,
  accession_no: "0000320193-24-000001",
  success: true,
  total_duration_ms: 1850)

# Pattern: Complete pipeline with FilingJourney
puts "\nPattern: Complete filing pipeline"
puts <<~CODE
  class FilingPipeline
    def initialize(client, logger)
      @client = client
      @logger = logger
    end

    def process_filing(stream_filing)
      accession_no = stream_filing.accession_no
      start_time = Time.now

      # Stage 1: Log detection
      SecApi::FilingJourney.log_detected(@logger, :info,
        accession_no: accession_no,
        ticker: stream_filing.ticker,
        form_type: stream_filing.form_type,
        latency_ms: stream_filing.latency_ms
      )

      # Stage 2: Query for full details
      query_start = Time.now
      full_filing = @client.query
        .ticker(stream_filing.ticker)
        .form_type(stream_filing.form_type)
        .limit(1)
        .search
        .first

      SecApi::FilingJourney.log_queried(@logger, :info,
        accession_no: accession_no,
        found: !full_filing.nil?,
        duration_ms: SecApi::FilingJourney.calculate_duration_ms(query_start)
      )

      # Stage 3: Extract XBRL
      extract_start = Time.now
      xbrl_data = @client.xbrl.to_json(full_filing)

      SecApi::FilingJourney.log_extracted(@logger, :info,
        accession_no: accession_no,
        facts_count: xbrl_data&.facts&.size || 0,
        duration_ms: SecApi::FilingJourney.calculate_duration_ms(extract_start)
      )

      # Stage 4: Process
      process_xbrl_data(xbrl_data)

      SecApi::FilingJourney.log_processed(@logger, :info,
        accession_no: accession_no,
        success: true,
        total_duration_ms: SecApi::FilingJourney.calculate_duration_ms(start_time)
      )

    rescue => e
      SecApi::FilingJourney.log_processed(@logger, :error,
        accession_no: accession_no,
        success: false,
        total_duration_ms: SecApi::FilingJourney.calculate_duration_ms(start_time),
        error_class: e.class.name
      )
      raise
    end
  end
CODE

# =============================================================================
# SECTION 8: Complete Production Configuration
# =============================================================================

puts "\n" + "=" * 60
puts "SECTION 8: Complete Production Configuration"
puts "=" * 60

puts "\nComplete production setup with all observability:"
puts <<~CODE
  require 'sec_api'
  require 'datadog/statsd'

  statsd = Datadog::Statsd.new('localhost', 8125)

  config = SecApi::Config.new(
    api_key: ENV.fetch("SECAPI_API_KEY"),

    # Automatic logging
    logger: Rails.logger,
    log_level: :info,
    default_logging: true,

    # Automatic metrics
    metrics_backend: statsd,

    # Rate limiting observability
    rate_limit_threshold: 0.2,
    on_throttle: ->(info) {
      Rails.logger.info("Rate limit throttle", info)
    },
    on_queue: ->(info) {
      Rails.logger.warn("Request queued", info)
    },

    # Error tracking (custom, overrides default_logging)
    on_error: ->(request_id:, error:, url:, method:) {
      # Log the error
      SecApi::StructuredLogger.log_error(Rails.logger, :error,
        request_id: request_id, error: error, url: url, method: method)

      # Also send to Bugsnag
      Bugsnag.notify(error) do |report|
        report.add_metadata(:sec_api, {request_id: request_id, url: url})
      end
    },

    # Stream monitoring
    stream_latency_warning_threshold: 120.0,
    on_filing: ->(filing:, latency_ms:, received_at:) {
      statsd.histogram("sec_api.stream.latency_ms", latency_ms,
        tags: ["form_type:\#{filing.form_type}"])
    },
    on_reconnect: ->(info) {
      Rails.logger.warn("Stream reconnected", info)
      statsd.increment("sec_api.stream.reconnected")
    },
    on_callback_error: ->(info) {
      Bugsnag.notify(info[:error])
    }
  )

  client = SecApi::Client.new(config)
CODE

puts "\n" + "=" * 60
puts "Examples completed successfully!"
puts "=" * 60
