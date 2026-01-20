# Migration Guide: v0.1.0 to v1.0.0

> **Version:** v1.0.0
> **Upgrade From:** v0.1.0
> **Last Updated:** 2026-01-13

This guide covers all breaking changes and new features when upgrading from sec_api v0.1.0 to v1.0.0. Follow this guide to ensure a smooth migration.

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Quick Migration Checklist](#quick-migration-checklist)
3. [Breaking Changes](#breaking-changes)
   - [Response Type Changes](#response-type-changes)
   - [Exception Hierarchy Changes](#exception-hierarchy-changes)
   - [Query Builder DSL](#query-builder-dsl)
   - [XBRL Endpoint Availability](#xbrl-endpoint-availability)
4. [New Features in v1.0.0](#new-features-in-v100)
   - [Rate Limiting Intelligence](#rate-limiting-intelligence)
   - [Retry Middleware with Exponential Backoff](#retry-middleware-with-exponential-backoff)
   - [WebSocket Streaming API](#websocket-streaming-api)
   - [Observability Hooks](#observability-hooks)
   - [Structured Logging](#structured-logging)
   - [Metrics Exposure](#metrics-exposure)
   - [Filing Journey Tracking](#filing-journey-tracking)
   - [Automatic Pagination](#automatic-pagination)
5. [Configuration Changes](#configuration-changes)
6. [Deprecations](#deprecations)
7. [Troubleshooting](#troubleshooting)

---

## Executive Summary

**sec_api v1.0.0** is a production-grade release with significant improvements over v0.1.0:

- **Type Safety:** All API responses now return immutable, thread-safe Dry::Struct value objects instead of raw hashes
- **Error Handling:** Typed exception hierarchy with automatic retry for transient failures
- **Query Builder:** Fluent DSL replaces raw query string construction
- **Observability:** Built-in instrumentation, structured logging, and metrics support
- **Real-Time:** WebSocket streaming API for filing notifications
- **Resilience:** Intelligent rate limiting and exponential backoff retry logic

**Why Upgrade?**

- 95%+ automatic recovery from transient API failures
- Thread-safe for concurrent usage (Sidekiq, background jobs)
- Zero-tolerance error handling prevents silent data loss
- Production monitoring integration via metrics and callbacks

---

## Quick Migration Checklist

Use this checklist to verify your migration is complete:

### Required Changes

- [ ] **Update gem version** in Gemfile: `gem "sec_api", "~> 1.0"`
- [ ] **Run `bundle update sec_api`** to install v1.0.0
- [ ] **Replace hash access with method calls** in all API response handling:
  - `result["ticker"]` → `result.ticker`
  - `result["formType"]` → `result.form_type`
  - `result["filedAt"]` → `result.filed_at`
- [ ] **Update exception handling** to use new typed exceptions:
  - Generic `rescue => e` → specific `rescue SecApi::RateLimitError`
  - Add handling for `TransientError` vs `PermanentError`
- [ ] **Migrate raw Lucene queries** to Query Builder DSL:
  - `search(query: 'ticker:AAPL')` → `.ticker("AAPL").search`
- [ ] **Update date range calls** to use keyword arguments:
  - `.date_range("2020-01-01", "2023-12-31")` → `.date_range(from: "2020-01-01", to: "2023-12-31")`

### Recommended Additions

- [ ] **Configure retry settings** if defaults don't suit your use case:
  ```ruby
  config = SecApi::Config.new(
    api_key: ENV["SEC_API_KEY"],
    retry_max_attempts: 5,
    retry_initial_delay: 1.0
  )
  ```
- [ ] **Set up structured logging** for production monitoring:
  ```ruby
  config = SecApi::Config.new(
    api_key: ENV["SEC_API_KEY"],
    logger: Rails.logger,
    default_logging: true
  )
  ```
- [ ] **Add error tracking callback** for alerting:
  ```ruby
  on_error: ->(request_id:, error:, url:, method:) {
    Bugsnag.notify(error)
  }
  ```
- [ ] **Configure metrics backend** if using StatsD/Datadog:
  ```ruby
  metrics_backend: StatsD.new('localhost', 8125)
  ```

### Testing Your Migration

- [ ] **Run your test suite** - existing tests should pass with response type updates
- [ ] **Verify error handling** - test with invalid API key, network failures
- [ ] **Check query results** - ensure typed objects work with your code
- [ ] **Test XBRL extraction** - verify `client.xbrl.to_json` works

### Optional: New Features to Enable

- [ ] **WebSocket streaming** for real-time filing notifications
- [ ] **Auto-pagination** with `.auto_paginate` for large result sets
- [ ] **Filing journey tracking** for end-to-end observability

---

## Breaking Changes

### Response Type Changes

**Impact:** All API methods now return typed value objects instead of raw hashes.

All API responses are now wrapped in immutable [Dry::Struct](https://dry-rb.org/gems/dry-struct/) value objects. This provides type safety, thread safety for concurrent access, and a clean method-based interface.

#### Query Results: Filings Collection

**v0.1.0 (OLD):**
```ruby
result = client.query.search(query: 'ticker:AAPL AND formType:"10-K"')
result.each do |hash|
  puts hash["accessionNo"]    # Hash access with string keys
  puts hash["formType"]
  puts hash["filedAt"]
end
```

**v1.0.0 (NEW):**
```ruby
result = client.query.ticker("AAPL").form_type("10-K").search
result.each do |filing|
  puts filing.accession_no    # Method calls (snake_case)
  puts filing.form_type
  puts filing.filed_at        # Returns Date object
end
```

**Key Changes:**
- `result` is now a `SecApi::Collections::Filings` object (includes Enumerable)
- Each item is a `SecApi::Objects::Filing` struct
- Use method calls instead of hash access: `filing.ticker` not `hash["ticker"]`
- Date fields return Ruby `Date` objects instead of strings
- All objects are frozen and thread-safe

#### Filing Object Attributes

| v0.1.0 Hash Key | v1.0.0 Method | Type |
|-----------------|---------------|------|
| `hash["ticker"]` | `filing.ticker` | String |
| `hash["cik"]` | `filing.cik` | String |
| `hash["formType"]` | `filing.form_type` | String |
| `hash["filedAt"]` | `filing.filed_at` | Date |
| `hash["accessionNo"]` | `filing.accession_no` | String |
| `hash["companyName"]` | `filing.company_name` | String |
| `hash["linkToHtml"]` | `filing.html_url` | String |
| `hash["linkToTxt"]` | `filing.txt_url` | String |
| `hash["entities"]` | `filing.entities` | Array<Entity> |
| `hash["documentFormatFiles"]` | `filing.documents` | Array<DocumentFormatFile> |
| `hash["dataFiles"]` | `filing.data_files` | Array<DataFile> |

#### Mapping Results: Entity Object

**v0.1.0 (OLD):**
```ruby
result = client.mapping.resolve_ticker("AAPL")
puts result["cik"]
puts result["companyName"]
```

**v1.0.0 (NEW):**
```ruby
entity = client.mapping.ticker("AAPL")
puts entity.cik       # => "0000320193"
puts entity.name      # => "Apple Inc."
puts entity.ticker    # => "AAPL"
puts entity.exchange  # => "NASDAQ"
```

**Key Changes:**
- Returns `SecApi::Objects::Entity` struct
- Method names use snake_case: `company_name` → `name`
- All attributes accessible via methods

#### Extractor Results: ExtractedData Object

**v0.1.0 (OLD):**
```ruby
result = client.extractor.extract(url, section: "risk_factors")
puts result["text"]
```

**v1.0.0 (NEW):**
```ruby
extracted = client.extractor.extract(url, section: "risk_factors")
puts extracted.text
puts extracted.sections[:risk_factors]  # Section access
puts extracted.risk_factors             # Dynamic method access
```

**Key Changes:**
- Returns `SecApi::ExtractedData` struct
- Sections accessible via hash or dynamic methods
- Thread-safe with deep-frozen nested structures

#### Collection Classes

v1.0.0 introduces collection classes that wrap arrays of results:

| Endpoint | Collection Class | Item Class |
|----------|------------------|------------|
| `client.query.search` | `SecApi::Collections::Filings` | `SecApi::Objects::Filing` |
| `client.query.fulltext(...)` | `SecApi::Collections::FulltextResults` | `SecApi::Objects::FulltextResult` |

**Collection Features:**
- Implements `Enumerable` for `each`, `map`, `select`, etc.
- `count` returns total API results (not just current page)
- `has_more?` checks for additional pages
- `fetch_next_page` retrieves next page
- `auto_paginate` returns lazy enumerator for all results

```ruby
filings = client.query.ticker("AAPL").search

# Enumerable methods
filings.each { |f| puts f.ticker }
filings.map(&:form_type)
filings.select { |f| f.form_type == "10-K" }

# Pagination metadata
filings.count        # Total across all pages
filings.has_more?    # More pages available?

# Fetch all pages lazily
filings.auto_paginate.each { |f| process(f) }
```

### Exception Hierarchy Changes

**Impact:** Generic exceptions replaced with typed exception classes that enable automatic retry and precise error handling.

v1.0.0 introduces a structured exception hierarchy that distinguishes between retryable (transient) and non-retryable (permanent) errors. The retry middleware automatically retries transient errors, while permanent errors fail immediately.

#### Exception Hierarchy Tree

```
SecApi::Error (base class)
├── SecApi::ConfigurationError     # Invalid/missing configuration
│
├── SecApi::TransientError         # Auto-retry eligible (temporary failures)
│   ├── SecApi::RateLimitError     # 429 Too Many Requests
│   ├── SecApi::NetworkError       # Timeouts, connection failures, SSL errors
│   └── SecApi::ServerError        # 500-504 Server errors
│
└── SecApi::PermanentError         # Fail fast (no retry)
    ├── SecApi::AuthenticationError # 401, 403 Invalid/unauthorized API key
    ├── SecApi::NotFoundError       # 404 Resource not found
    └── SecApi::ValidationError     # 400, 422 Invalid request parameters
```

#### Before/After: Rescue Blocks

**v0.1.0 (OLD):**
```ruby
begin
  client.query.search(query: "ticker:AAPL")
rescue => e
  # All errors caught generically - can't distinguish error types
  puts e.message
  # Can't tell if retry might help
  # No request ID for correlation
end
```

**v1.0.0 (NEW):**
```ruby
begin
  client.query.ticker("AAPL").search
rescue SecApi::RateLimitError => e
  # Auto-retry exhausted (5 retries by default)
  logger.warn("Rate limit hit: #{e.message}")
  logger.info("Retry after: #{e.retry_after}s") if e.retry_after

rescue SecApi::AuthenticationError => e
  # Permanent: Invalid API key, no retry
  logger.error("Auth failed: #{e.message}")
  notify_developer("Check API key configuration")

rescue SecApi::TransientError => e
  # Catch-all for retryable errors (network, server)
  logger.error("Transient failure after retries: #{e.message}")
  schedule_retry_later

rescue SecApi::PermanentError => e
  # Catch-all for non-retryable errors (not found, validation)
  logger.error("Permanent failure: #{e.message}")

rescue SecApi::ConfigurationError => e
  # Missing API key or invalid configuration
  logger.error("Configuration error: #{e.message}")
end
```

#### Automatic Retry Behavior

**TransientError subclasses are automatically retried:**
- Default: 5 retry attempts
- Exponential backoff with jitter
- Honors `Retry-After` header when present

```ruby
# These errors are auto-retried before being raised:
SecApi::RateLimitError   # 429 responses
SecApi::NetworkError     # Timeouts, connection failures
SecApi::ServerError      # 500, 502, 503, 504 responses
```

**PermanentError subclasses fail immediately:**
```ruby
# These errors are NOT retried:
SecApi::AuthenticationError  # 401, 403 - fix API key
SecApi::NotFoundError        # 404 - resource doesn't exist
SecApi::ValidationError      # 400, 422 - fix request parameters
```

#### Request Correlation IDs

All errors include a `request_id` for tracing through logs and monitoring:

```ruby
begin
  client.query.ticker("AAPL").search
rescue SecApi::Error => e
  # Error message includes request_id prefix:
  # "[abc123-def456] Rate limit exceeded (429 Too Many Requests)"
  puts e.message

  # Access request_id directly for logging/monitoring:
  logger.error("Request failed",
    request_id: e.request_id,
    error_class: e.class.name,
    message: e.message
  )

  # Send to error tracking service
  Bugsnag.notify(e, metadata: { request_id: e.request_id })
end
```

#### RateLimitError Additional Context

`RateLimitError` includes retry timing information:

```ruby
rescue SecApi::RateLimitError => e
  e.retry_after  # Seconds to wait (from Retry-After header)
  e.reset_at     # Time when rate limit resets (from X-RateLimit-Reset header)

  if e.reset_at
    wait_time = e.reset_at - Time.now
    sleep(wait_time) if wait_time.positive?
  end
end
```

#### Pattern: Comprehensive Error Handling

```ruby
def fetch_filings(ticker)
  client.query.ticker(ticker).search
rescue SecApi::ConfigurationError => e
  # Fail fast - cannot proceed without valid configuration
  raise

rescue SecApi::AuthenticationError => e
  # Fail fast - invalid API key
  Rails.logger.error("SEC API auth failed", request_id: e.request_id)
  raise

rescue SecApi::RateLimitError => e
  # Rate limit exhausted after retries - queue for later
  SecFilingJob.perform_in(e.retry_after || 60, ticker)
  nil

rescue SecApi::TransientError => e
  # Network/server issues after retries - queue for retry
  SecFilingJob.perform_in(30, ticker)
  nil

rescue SecApi::PermanentError => e
  # Not found or validation error - log and continue
  Rails.logger.warn("Permanent error for #{ticker}", error: e.message)
  nil
end
```

### Query Builder DSL

**Impact:** Raw Lucene query strings replaced with fluent, chainable builder methods.

v1.0.0 introduces an ActiveRecord-style query builder that provides type-safe, discoverable filtering methods. Each method returns `self` for chaining, with `.search` as the terminal method.

#### Before/After: Query Syntax

**v0.1.0 (OLD):**
```ruby
# Raw Lucene query string construction
result = client.query.search(
  query: 'ticker:AAPL AND formType:"10-K"',
  from: "0",
  size: "10"
)

# Error-prone string interpolation
ticker = "AAPL"
form = "10-K"
result = client.query.search(
  query: "ticker:#{ticker} AND formType:\"#{form}\""
)
```

**v1.0.0 (NEW):**
```ruby
# Fluent, chainable methods
result = client.query
  .ticker("AAPL")
  .form_type("10-K")
  .limit(10)
  .search

# Type-safe, no string interpolation
ticker = "AAPL"
form = "10-K"
result = client.query
  .ticker(ticker)
  .form_type(form)
  .search
```

#### Builder Methods Reference

| Method | Description | Example |
|--------|-------------|---------|
| `.ticker(*tickers)` | Filter by stock ticker(s) | `.ticker("AAPL")` or `.ticker("AAPL", "TSLA")` |
| `.cik(cik_number)` | Filter by CIK (leading zeros stripped) | `.cik("0000320193")` → `cik:320193` |
| `.form_type(*types)` | Filter by SEC form type(s) | `.form_type("10-K", "10-Q")` |
| `.date_range(from:, to:)` | Filter by filing date range | `.date_range(from: "2020-01-01", to: "2023-12-31")` |
| `.search_text(keywords)` | Full-text search in content | `.search_text("merger acquisition")` |
| `.limit(count)` | Limit results (default: 50) | `.limit(100)` |

#### Terminal Methods

| Method | Description | Returns |
|--------|-------------|---------|
| `.search` | Execute query, return first page | `SecApi::Collections::Filings` |
| `.auto_paginate` | Execute query with lazy pagination | `Enumerator::Lazy` |

#### Date Range Accepts Multiple Types

```ruby
# ISO 8601 strings
.date_range(from: "2020-01-01", to: "2023-12-31")

# Ruby Date objects
.date_range(from: Date.new(2020, 1, 1), to: Date.today)

# Time objects (including ActiveSupport::TimeWithZone)
.date_range(from: 1.year.ago, to: Time.now)
```

#### Multiple Value Support

```ruby
# Multiple tickers (OR logic)
client.query.ticker("AAPL", "TSLA", "MSFT").search
# → ticker:(AAPL, TSLA, MSFT)

# Multiple form types (OR logic)
client.query.form_type("10-K", "10-Q", "8-K").search
# → formType:("10-K" OR "10-Q" OR "8-K")
```

#### International Filing Support

International SEC forms work identically to domestic forms:

```ruby
# Form 20-F: Foreign private issuer annual reports
client.query.ticker("NMR").form_type("20-F").search

# Form 40-F: Canadian issuer annual reports (MJDS)
client.query.ticker("ABX").form_type("40-F").search

# Form 6-K: Foreign private issuer current reports
client.query.ticker("NMR").form_type("6-K").search

# Mix domestic and international
client.query.form_type("10-K", "20-F", "40-F").search
```

#### Complex Query Examples

```ruby
# Multi-year backfill for specific company
client.query
  .ticker("AAPL")
  .form_type("10-K", "10-Q")
  .date_range(from: "2018-01-01", to: Date.today)
  .auto_paginate
  .each { |filing| process(filing) }

# Search for M&A announcements
client.query
  .form_type("8-K")
  .search_text("merger acquisition")
  .date_range(from: "2023-01-01", to: Date.today)
  .limit(100)
  .search

# Debug: Inspect generated Lucene query
query = client.query.ticker("AAPL").form_type("10-K")
puts query.to_lucene
# → "ticker:AAPL AND formType:\"10-K\""
```

#### Backward Compatibility

Raw Lucene queries still work but are deprecated:

```ruby
# Still works (deprecated)
client.query.search('ticker:AAPL AND formType:"10-K"')

# Recommended
client.query.ticker("AAPL").form_type("10-K").search
```

### XBRL Endpoint Availability

**Impact:** The XBRL proxy was orphaned in v0.1.0 (not accessible via `client.xbrl`). Now fully wired and functional.

#### What Changed

In v0.1.0, the `SecApi::Xbrl` class existed but was never wired to the `Client` class. Calling `client.xbrl` would fail with `NoMethodError`. v1.0.0 fixes this by:

1. Wiring `client.xbrl` to return a cached `Xbrl` proxy instance
2. Returning immutable `XbrlData` objects instead of raw hashes
3. Supporting multiple input formats (URL, accession number, Filing object)

#### Using the XBRL Endpoint

```ruby
client = SecApi::Client.new(api_key: "your_api_key")

# Extract XBRL data using SEC filing URL
xbrl = client.xbrl.to_json(
  "https://www.sec.gov/Archives/edgar/data/320193/000032019323000106/aapl-20230930.htm"
)

# Extract using accession number
xbrl = client.xbrl.to_json(accession_no: "0000320193-23-000106")

# Extract from Filing object (convenient)
filing = client.query.ticker("AAPL").form_type("10-K").search.first
xbrl = client.xbrl.to_json(filing)
```

#### XbrlData Object Structure

```ruby
xbrl = client.xbrl.to_json(filing)

# Access financial statement sections
xbrl.statements_of_income     # Income statement elements
xbrl.balance_sheets           # Balance sheet elements
xbrl.statements_of_cash_flows # Cash flow statement elements
xbrl.cover_page               # Document and entity information (DEI)

# Each section is a Hash: element_name => Array<Fact>
revenue_facts = xbrl.statements_of_income["RevenueFromContractWithCustomerExcludingAssessedTax"]
revenue_facts.first.value       # Raw string value
revenue_facts.first.to_numeric  # => 394328000000.0
revenue_facts.first.period      # Period object with start_date, end_date
```

#### Discovering Available Elements

Element names vary by taxonomy (US GAAP vs IFRS). Use helper methods:

```ruby
# Get all available element names
xbrl.element_names
# => ["Assets", "CashAndCashEquivalents", "Revenue", ...]

# Search for specific elements
xbrl.element_names.grep(/Revenue/)
# => ["RevenueFromContractWithCustomerExcludingAssessedTax"]

# Detect taxonomy (heuristic)
xbrl.taxonomy_hint  # => :us_gaap, :ifrs, or :unknown

# Validate data presence
xbrl.valid?  # => true if any financial statement section is present
```

#### US GAAP vs IFRS Element Names

| Concept | US GAAP Element | IFRS Element |
|---------|-----------------|--------------|
| Revenue | `RevenueFromContractWithCustomerExcludingAssessedTax` | `Revenue` |
| Net Income | `NetIncomeLoss` | `ProfitLoss` |
| Cost of Sales | `CostOfGoodsAndServicesSold` | `CostOfSales` |
| Equity | `StockholdersEquity` | `Equity` |
| Operating Cash | `NetCashProvidedByUsedInOperatingActivities` | `CashFlowsFromUsedInOperatingActivities` |

```ruby
# Pattern for handling both taxonomies
case xbrl.taxonomy_hint
when :us_gaap
  revenue = xbrl.statements_of_income["RevenueFromContractWithCustomerExcludingAssessedTax"]
when :ifrs
  revenue = xbrl.statements_of_income["Revenue"]
else
  # Fall back to discovery
  revenue_key = xbrl.element_names.find { |n| n.include?("Revenue") }
  revenue = xbrl.statements_of_income[revenue_key]
end
```

---

## New Features in v1.0.0

### Rate Limiting Intelligence

v1.0.0 includes intelligent rate limit handling:

- **Proactive throttling:** Automatically sleeps when remaining quota drops below threshold (default: 10%)
- **Request queueing:** Queues requests when rate limit is exhausted (remaining = 0)
- **Header tracking:** Parses `X-RateLimit-*` headers from every response

```ruby
config = SecApi::Config.new(
  api_key: "...",
  rate_limit_threshold: 0.2,  # Throttle at 20% remaining

  # Callbacks for monitoring
  on_throttle: ->(info) {
    puts "Throttling for #{info[:delay]}s, #{info[:remaining]} requests remaining"
  },
  on_queue: ->(info) {
    puts "Request queued, #{info[:queue_size]} waiting"
  },
  on_rate_limit: ->(info) {
    puts "429 received, retry in #{info[:retry_after]}s"
  }
)
```

### Retry Middleware with Exponential Backoff

Automatic retry for transient failures with exponential backoff:

```ruby
config = SecApi::Config.new(
  api_key: "...",
  retry_max_attempts: 5,        # Default: 5 retries
  retry_initial_delay: 1.0,     # Start with 1 second
  retry_max_delay: 60.0,        # Cap at 60 seconds
  retry_backoff_factor: 2,      # 1s, 2s, 4s, 8s, 16s...

  on_retry: ->(info) {
    puts "Retry #{info[:attempt]}/#{info[:max_attempts]}: #{info[:error_class]}"
  }
)
```

**Retry-eligible errors:** `RateLimitError`, `NetworkError`, `ServerError` (all `TransientError` subclasses)

### WebSocket Streaming API

Real-time SEC filing notifications via WebSocket:

```ruby
client = SecApi::Client.new

# Subscribe to all filings
client.stream.subscribe do |filing|
  puts "#{filing.ticker}: #{filing.form_type} at #{filing.filed_at}"
end

# Filter by tickers and/or form types
client.stream.subscribe(tickers: ["AAPL"], form_types: ["10-K", "8-K"]) do |filing|
  ProcessFilingJob.perform_async(filing.accession_no)
end

# Check connection status
client.stream.connected?

# Close connection
client.stream.close
```

**Stream features:**
- Client-side filtering (tickers, form_types)
- Auto-reconnect with exponential backoff (configurable)
- Latency tracking (`filing.latency_ms`, `filing.latency_seconds`)
- Best-effort delivery (use Query API to backfill gaps)

### Observability Hooks

Instrumentation callbacks for monitoring and APM integration:

```ruby
config = SecApi::Config.new(
  api_key: "...",

  # Request lifecycle callbacks
  on_request: ->(request_id:, method:, url:, headers:) {
    Rails.logger.info("SEC API request", request_id: request_id, method: method)
  },

  on_response: ->(request_id:, status:, duration_ms:, url:, method:) {
    StatsD.histogram("sec_api.duration_ms", duration_ms)
  },

  on_retry: ->(request_id:, attempt:, max_attempts:, error_class:, error_message:, will_retry_in:) {
    StatsD.increment("sec_api.retries")
  },

  on_error: ->(request_id:, error:, url:, method:) {
    Bugsnag.notify(error, request_id: request_id)
  },

  # Stream-specific callbacks
  on_filing: ->(filing:, latency_ms:, received_at:) {
    StatsD.histogram("sec_api.stream.latency_ms", latency_ms)
  },

  on_reconnect: ->(attempt_count:, downtime_seconds:) {
    StatsD.increment("sec_api.stream.reconnected")
  }
)
```

### Structured Logging

JSON-formatted logs for log aggregation tools (ELK, Datadog, Splunk):

```ruby
config = SecApi::Config.new(
  api_key: "...",
  logger: Rails.logger,
  log_level: :info,
  default_logging: true  # Enable automatic structured logging
)

# Log output format (JSON):
# {"event":"secapi.request.start","request_id":"abc-123","method":"GET","url":"https://...","timestamp":"2024-01-15T10:30:00.123Z"}
# {"event":"secapi.request.complete","request_id":"abc-123","status":200,"duration_ms":150,...}
# {"event":"secapi.request.retry","request_id":"abc-123","attempt":1,...}
# {"event":"secapi.request.error","request_id":"abc-123","error_class":"SecApi::ServerError",...}
```

Or use `SecApi::StructuredLogger` directly:

```ruby
SecApi::StructuredLogger.log_request(logger, :info, request_id: id, method: :get, url: url)
SecApi::StructuredLogger.log_response(logger, :info, request_id: id, status: 200, duration_ms: 150, ...)
```

### Metrics Exposure

Automatic metrics collection via StatsD-compatible backends:

```ruby
require 'statsd-ruby'
statsd = StatsD.new('localhost', 8125)

config = SecApi::Config.new(
  api_key: "...",
  metrics_backend: statsd  # Or Datadog::Statsd.new(...)
)

# Metrics automatically collected:
# sec_api.requests.total       (counter, tags: method, status)
# sec_api.requests.duration_ms (histogram)
# sec_api.retries.total        (counter, tags: error_class, attempt)
# sec_api.errors.total         (counter, tags: error_class)
# sec_api.rate_limit.throttle  (counter)
# sec_api.rate_limit.queue     (gauge)
```

### Filing Journey Tracking

Track filing lifecycle from detection through processing:

```ruby
# In your stream handler:
client.stream.subscribe do |filing|
  detected_at = Time.now

  # Stage 1: Detection
  SecApi::FilingJourney.log_detected(logger, :info,
    accession_no: filing.accession_no,
    ticker: filing.ticker,
    form_type: filing.form_type
  )

  # Stage 2: Query for metadata
  full_filing = client.query.ticker(filing.ticker).limit(1).search.first
  SecApi::FilingJourney.log_queried(logger, :info,
    accession_no: filing.accession_no,
    found: !full_filing.nil?
  )

  # Stage 3: XBRL extraction
  xbrl = client.xbrl.to_json(filing)
  SecApi::FilingJourney.log_extracted(logger, :info,
    accession_no: filing.accession_no,
    facts_count: xbrl.element_names.size
  )

  # Stage 4: Processing complete
  total_ms = SecApi::FilingJourney.calculate_duration_ms(detected_at)
  SecApi::FilingJourney.log_processed(logger, :info,
    accession_no: filing.accession_no,
    success: true,
    total_duration_ms: total_ms
  )
end

# Query logs by accession_no for complete journey:
# ELK:     accession_no:"0000320193-24-000001" AND event:secapi.filing.journey.*
# Datadog: @accession_no:0000320193-24-000001 @event:secapi.filing.journey.*
```

### Automatic Pagination

Lazy enumeration through all search results:

```ruby
# Auto-paginate through all results (lazy evaluation)
client.query
  .ticker("AAPL")
  .form_type("10-K", "10-Q")
  .date_range(from: "2018-01-01", to: Date.today)
  .auto_paginate
  .each { |filing| process(filing) }

# With Enumerable methods (also lazy)
client.query.ticker("AAPL").auto_paginate
  .select { |f| f.form_type == "10-K" }
  .take(100)
  .each { |f| process(f) }

# Manual pagination still available
filings = client.query.ticker("AAPL").search
while filings.has_more?
  filings.each { |f| process(f) }
  filings = filings.fetch_next_page
end
```

---

## Configuration Changes

### New Configuration Options

v1.0.0 adds many new configuration options. All are optional with sensible defaults.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `retry_max_attempts` | Integer | 5 | Maximum retry attempts for transient errors |
| `retry_initial_delay` | Float | 1.0 | Initial retry delay (seconds) |
| `retry_max_delay` | Float | 60.0 | Maximum retry delay (seconds) |
| `retry_backoff_factor` | Integer | 2 | Exponential backoff multiplier |
| `request_timeout` | Integer | 30 | HTTP request timeout (seconds) |
| `rate_limit_threshold` | Float | 0.1 | Throttle threshold (0.0-1.0) |
| `queue_wait_warning_threshold` | Integer | 300 | Warn if queue wait exceeds (seconds) |
| `logger` | Logger | nil | Logger instance for structured logging |
| `log_level` | Symbol | :info | Log level (:debug, :info, :warn, :error) |
| `default_logging` | Boolean | false | Enable automatic structured logging |
| `metrics_backend` | Object | nil | StatsD-compatible metrics backend |

**Stream-specific options:**

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `stream_max_reconnect_attempts` | Integer | 10 | Max reconnection attempts |
| `stream_initial_reconnect_delay` | Float | 1.0 | Initial reconnect delay (seconds) |
| `stream_max_reconnect_delay` | Float | 60.0 | Max reconnect delay (seconds) |
| `stream_backoff_multiplier` | Integer | 2 | Reconnect backoff multiplier |
| `stream_latency_warning_threshold` | Float | 120.0 | Warn if latency exceeds (seconds) |

**Callback options:**

| Option | Invoked When |
|--------|--------------|
| `on_request` | Before each REST API request |
| `on_response` | After each REST API response |
| `on_retry` | Before each retry attempt |
| `on_error` | On final failure (all retries exhausted) |
| `on_throttle` | When proactive throttling occurs |
| `on_rate_limit` | When 429 response received |
| `on_queue` | When request queued (rate limit exhausted) |
| `on_dequeue` | When request exits queue |
| `on_excessive_wait` | When queue wait exceeds threshold |
| `on_callback_error` | When stream callback raises exception |
| `on_reconnect` | When stream reconnection succeeds |
| `on_filing` | When filing received via stream |

### Configuration Sources

Configuration can be provided via (in order of precedence):

1. **Constructor arguments** (highest priority)
2. **YAML file:** `config/secapi.yml`
3. **Environment variables** (lowest priority)

```ruby
# Constructor (highest priority)
config = SecApi::Config.new(api_key: "from_constructor")

# YAML file (config/secapi.yml)
# secapi:
#   api_key: "from_yaml"
#   retry_max_attempts: 3

# Environment variables (SECAPI_ prefix)
# SECAPI_API_KEY=from_env
# SECAPI_RETRY_MAX_ATTEMPTS=3
```

### Minimal Configuration

```ruby
# v0.1.0 style (still works)
client = SecApi::Client.new(api_key: ENV["SEC_API_KEY"])

# v1.0.0 style (recommended)
config = SecApi::Config.new(api_key: ENV["SEC_API_KEY"])
client = SecApi::Client.new(config: config)

# Or use environment variable directly
# Set SECAPI_API_KEY in your environment
client = SecApi::Client.new
```

### Production-Ready Configuration

```ruby
config = SecApi::Config.new(
  api_key: ENV["SEC_API_KEY"],

  # Retry settings
  retry_max_attempts: 5,
  retry_initial_delay: 1.0,
  retry_max_delay: 60.0,
  retry_backoff_factor: 2,

  # Rate limiting
  rate_limit_threshold: 0.1,

  # Logging
  logger: Rails.logger,
  log_level: :info,
  default_logging: true,

  # Metrics (optional)
  metrics_backend: StatsD.new('localhost', 8125),

  # Error tracking
  on_error: ->(request_id:, error:, url:, method:) {
    Bugsnag.notify(error, request_id: request_id)
  }
)

client = SecApi::Client.new(config: config)
```

---

## Deprecations

### Deprecated in v1.0.0

| Deprecated | Replacement | Notes |
|------------|-------------|-------|
| Raw Lucene query strings | Query Builder DSL | Still works, will be removed in v2.0 |
| `client.query.search(query: "...")` | `client.query.ticker(...).search` | Fluent DSL is preferred |

---

## Troubleshooting

### Common Migration Issues

#### 1. NoMethodError on API responses

**Problem:** `undefined method 'ticker' for {"ticker"=>"AAPL"...}:Hash`

**Cause:** Code expects hash access but v1.0.0 returns typed objects.

**Fix:** Replace hash access with method calls:
```ruby
# Old
result["ticker"]
result["formType"]

# New
result.ticker
result.form_type
```

#### 2. TypeError when accessing nested data

**Problem:** `TypeError: can't convert String to Integer`

**Cause:** Trying to use string keys on typed objects.

**Fix:** Use dot notation for all attributes:
```ruby
# Old
filing["entities"][0]["name"]

# New
filing.entities.first.name
```

#### 3. Exception handling not working

**Problem:** `rescue => e` catches nothing when expected.

**Cause:** Catching wrong exception type.

**Fix:** Use the new exception hierarchy:
```ruby
# Catch specific errors
rescue SecApi::RateLimitError => e
rescue SecApi::TransientError => e  # Catch-all for retryable
rescue SecApi::PermanentError => e  # Catch-all for non-retryable
rescue SecApi::Error => e           # Catch any SecApi error
```

#### 4. Query builder returns no results

**Problem:** Query returns empty results when it shouldn't.

**Cause:** Using wrong method syntax.

**Fix:** Check method signatures:
```ruby
# Wrong - dates as positional args
.date_range("2020-01-01", "2023-12-31")

# Correct - dates as keyword args
.date_range(from: "2020-01-01", to: "2023-12-31")
```

#### 5. XBRL extraction fails

**Problem:** `ValidationError: XBRL data validation failed`

**Cause:** Filing may not have XBRL data, or URL is invalid.

**Fix:** Verify the filing has XBRL data:
```ruby
# Check filing has XBRL
if filing.respond_to?(:xbrl_url) && !filing.xbrl_url.to_s.empty?
  xbrl = client.xbrl.to_json(filing)
end

# Or use accession number
xbrl = client.xbrl.to_json(accession_no: filing.accession_no)
```

### Getting Help

- **GitHub Issues:** https://github.com/ljuti/sec_api/issues
- **sec-api.io Documentation:** https://sec-api.io/docs

