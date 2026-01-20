# sec_api

[![Gem Version](https://badge.fury.io/rb/sec_api.svg)](https://badge.fury.io/rb/sec_api)
[![CI](https://github.com/ljuti/sec_api/actions/workflows/main.yml/badge.svg)](https://github.com/ljuti/sec_api/actions/workflows/main.yml)
[![Ruby](https://img.shields.io/badge/ruby-3.1%2B-ruby.svg)](https://www.ruby-lang.org)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE.txt)
[![Documentation](https://img.shields.io/badge/docs-YARD-blue.svg)](https://rubydoc.info/gems/sec_api)

Production-grade Ruby client for accessing SEC EDGAR filings through the [sec-api.io](https://sec-api.io) API. Query, search, and extract structured financial data from 18+ million SEC filings with automatic retry, rate limiting, and comprehensive error handling.

## Features

- **Query Builder DSL** - Fluent, chainable interface for searching filings by ticker, CIK, form type, date range, and full-text keywords
- **Automatic Pagination** - Memory-efficient lazy enumeration through large result sets with `auto_paginate`
- **Entity Mapping** - Resolve tickers, CIKs, CUSIPs, and company names to entity records
- **XBRL Extraction** - Extract structured financial data from US GAAP and IFRS filings
- **Real-Time Streaming** - WebSocket notifications for new filings with <2 minute latency
- **Intelligent Rate Limiting** - Proactive throttling and request queueing to maximize throughput
- **Production Error Handling** - TransientError/PermanentError hierarchy with automatic retry
- **Observability Hooks** - Instrumentation callbacks for logging, metrics, and distributed tracing

## Installation

Add to your Gemfile:

```ruby
gem 'sec_api'
```

Or install directly:

```bash
gem install sec_api
```

## Quick Start

### Configuration

Set your API key via environment variable:

```bash
export SECAPI_API_KEY=your_api_key_here
```

Get your API key from [sec-api.io](https://sec-api.io).

Alternatively, create `config/secapi.yml`:

```yaml
api_key: <%= ENV['SECAPI_API_KEY'] %>
```

### Basic Usage

```ruby
require 'sec_api'

# Initialize client (auto-loads configuration)
client = SecApi::Client.new

# Query filings by ticker
filings = client.query.ticker("AAPL").form_type("10-K").search
filings.each do |filing|
  puts "#{filing.form_type} filed on #{filing.filed_at}"
end
```

## Usage Examples

### Query Builder

```ruby
# Simple ticker query
filings = client.query
  .ticker("AAPL")
  .form_type("10-K")
  .search

# Multiple tickers and form types with date range
filings = client.query
  .ticker("AAPL", "TSLA", "GOOGL")
  .form_type("10-K", "10-Q", "8-K")
  .date_range(from: "2020-01-01", to: Date.today)
  .limit(100)
  .search

# Full-text search
filings = client.query
  .ticker("META")
  .search_text("artificial intelligence")
  .search
```

### Automatic Pagination

```ruby
# Manual pagination
filings = client.query.ticker("AAPL").search
next_page = filings.fetch_next_page if filings.has_more?

# Automatic pagination for backfills (memory-efficient)
client.query
  .ticker("AAPL")
  .date_range(from: "2015-01-01", to: Date.today)
  .auto_paginate
  .each do |filing|
    # Process thousands of filings with constant memory usage
    process_filing(filing)
  end
```

### Entity Mapping

```ruby
# Ticker to entity
entity = client.mapping.ticker("AAPL")
puts "CIK: #{entity.cik}, Name: #{entity.name}"

# CIK to entity
entity = client.mapping.cik("0000320193")

# CUSIP lookup
entity = client.mapping.cusip("037833100")
```

### XBRL Data Extraction

```ruby
# Extract XBRL data from a filing
xbrl_data = client.xbrl.to_json(filing.xbrl_url)

# Access financial data by US GAAP element names
revenue = xbrl_data.statements_of_income["RevenueFromContractWithCustomerExcludingAssessedTax"]
assets = xbrl_data.balance_sheets["Assets"]

# Discover available elements
xbrl_data.element_names  # => ["Assets", "Revenue", ...]
xbrl_data.taxonomy_hint  # => :us_gaap or :ifrs
```

### Real-Time Streaming

```ruby
# Subscribe to filtered filings
client.stream.subscribe(
  tickers: ["AAPL", "TSLA"],
  form_types: ["10-K", "8-K"]
) do |filing|
  puts "New filing: #{filing.ticker} - #{filing.form_type}"
  ProcessFilingJob.perform_async(filing.accession_no)
end
```

### Error Handling

```ruby
begin
  filings = client.query.ticker("AAPL").search
rescue SecApi::RateLimitError => e
  # Automatically retried with exponential backoff
  # Only raised after max retries exhausted
  puts "Rate limited: retry after #{e.retry_after}s"
rescue SecApi::AuthenticationError => e
  # Permanent error - fix API key
  puts "Auth failed: #{e.message}"
rescue SecApi::TransientError => e
  # Network or server error - safe to retry
  retry
rescue SecApi::PermanentError => e
  # Don't retry - fix the request
  puts "Permanent error: #{e.message}"
end
```

### Observability

```ruby
# Configure instrumentation callbacks
config = SecApi::Config.new(
  api_key: ENV.fetch("SECAPI_API_KEY"),

  on_request: ->(request_id:, method:, url:, headers:) {
    Rails.logger.info("SEC API Request", request_id: request_id, url: url)
  },

  on_response: ->(request_id:, status:, duration_ms:, url:, method:) {
    StatsD.histogram("sec_api.request.duration_ms", duration_ms)
  },

  on_error: ->(request_id:, error:, url:, method:) {
    Bugsnag.notify(error)
  }
)

client = SecApi::Client.new(config)

# Or use automatic structured logging
client = SecApi::Client.new(
  api_key: ENV.fetch("SECAPI_API_KEY"),
  logger: Rails.logger,
  default_logging: true
)
```

## Architecture

### Client Proxy Pattern

```ruby
SecApi::Client
├── .query      # Query API proxy (fluent search builder)
├── .mapping    # Mapping API proxy (ticker/CIK resolution)
├── .extractor  # Extractor API proxy (document extraction)
├── .xbrl       # XBRL API proxy (financial data)
└── .stream     # Stream API proxy (WebSocket notifications)
```

### Exception Hierarchy

```
SecApi::Error (base)
├── TransientError (automatic retry)
│   ├── RateLimitError (429)
│   ├── ServerError (5xx)
│   └── NetworkError
└── PermanentError (fail immediately)
    ├── AuthenticationError (401/403)
    ├── NotFoundError (404)
    ├── ValidationError (400/422)
    └── ConfigurationError
```

### Middleware Stack

```
Request → Instrumentation → Retry → RateLimiter → ErrorHandler → Adapter → sec-api.io
```

## Configuration Options

All options can be set via YAML or environment variables:

| Option | Env Variable | Default | Description |
|--------|--------------|---------|-------------|
| `api_key` | `SECAPI_API_KEY` | _(required)_ | Your sec-api.io API key |
| `base_url` | `SECAPI_BASE_URL` | `https://api.sec-api.io` | API base URL |
| `retry_max_attempts` | `SECAPI_RETRY_MAX_ATTEMPTS` | `5` | Maximum retry attempts |
| `retry_initial_delay` | `SECAPI_RETRY_INITIAL_DELAY` | `1.0` | Initial retry delay (seconds) |
| `retry_max_delay` | `SECAPI_RETRY_MAX_DELAY` | `60` | Maximum retry delay (seconds) |
| `request_timeout` | `SECAPI_REQUEST_TIMEOUT` | `30` | HTTP request timeout (seconds) |
| `rate_limit_threshold` | `SECAPI_RATE_LIMIT_THRESHOLD` | `0.1` | Throttle when <10% quota remains |
| `default_logging` | - | `false` | Enable automatic structured logging |
| `metrics_backend` | - | `nil` | StatsD-compatible metrics backend |

## Requirements

- **Ruby:** 3.1.0 or higher
- **Dependencies:**
  - `faraday` - HTTP client
  - `faraday-retry` - Automatic retry middleware
  - `anyway_config` - Configuration management
  - `dry-struct` - Immutable value objects
  - `faye-websocket` - WebSocket client for streaming
  - `eventmachine` - Event-driven I/O

## Documentation

### API Reference

Generate YARD documentation:

```bash
bundle exec yard doc
open doc/index.html
```

### Usage Examples

See working examples in `docs/examples/`:

| File | Description |
|------|-------------|
| [query_builder.rb](docs/examples/query_builder.rb) | Query by ticker, CIK, form type, date range |
| [backfill_filings.rb](docs/examples/backfill_filings.rb) | Multi-year backfill with auto-pagination |
| [streaming_notifications.rb](docs/examples/streaming_notifications.rb) | Real-time WebSocket notifications |
| [instrumentation.rb](docs/examples/instrumentation.rb) | Logging, metrics, and observability |

### Migration Guide

Upgrading from v0.1.0? See the [Migration Guide](docs/migration-guide-v1.md) for breaking changes and upgrade instructions.

### Architecture Documentation

- [Product Requirements](_bmad-output/planning-artifacts/prd.md) - Complete requirements
- [Architecture](_bmad-output/planning-artifacts/architecture.md) - Technical decisions
- [Epics & Stories](_bmad-output/planning-artifacts/epics.md) - Implementation roadmap

## Development

### Setup

```bash
git clone https://github.com/ljuti/sec_api.git
cd sec_api
bin/setup
```

### Testing

```bash
bundle exec rspec              # Run tests
bundle exec standardrb         # Run linter
bundle exec rake               # Run both
```

### Interactive Console

```bash
bin/console
```

## Roadmap

### v0.1.0
- ✅ Basic query, search, mapping, extractor endpoints
- ✅ Configuration via anyway_config
- ✅ Immutable value objects (Dry::Struct)

### v1.0.0
- ✅ Production-grade error handling with TransientError/PermanentError
- ✅ Fluent query builder DSL
- ✅ Automatic pagination with lazy enumeration
- ✅ XBRL extraction with taxonomy detection
- ✅ Real-time streaming API (WebSocket)
- ✅ Intelligent rate limiting with proactive throttling
- ✅ Observability hooks (instrumentation callbacks)
- ✅ Structured logging and metrics integration
- ✅ 100% YARD documentation coverage
- ✅ Migration guide from v0.1.0

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/ljuti/sec_api.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/my-feature`)
3. Write tests for your changes
4. Ensure tests pass (`bundle exec rspec && bundle exec standardrb`)
5. Commit your changes (`git commit -am 'Add new feature'`)
6. Push to the branch (`git push origin feature/my-feature`)
7. Create a Pull Request

## License

The gem is available as open source under the terms of the [MIT License](LICENSE.txt).

## Support

- **GitHub Issues:** https://github.com/ljuti/sec_api/issues
- **Author:** Lauri Jutila
- **Email:** git@laurijutila.com

## Acknowledgments

This gem interacts with the [sec-api.io](https://sec-api.io) API. You'll need an API key from sec-api.io to use this gem.

---

**Status:** v1.0.0 released
