# sec_api

[![Gem Version](https://badge.fury.io/rb/sec_api.svg)](https://badge.fury.io/rb/sec_api)
[![Ruby](https://img.shields.io/badge/ruby-3.1%2B-ruby.svg)](https://www.ruby-lang.org)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE.txt)

Production-grade Ruby client for accessing SEC EDGAR filings through the [sec-api.io](https://sec-api.io) API. Query, search, and extract structured financial data from 18+ million SEC filings with automatic retry, rate limiting, and comprehensive error handling.

## Features

### Current (v0.1.0)

- **Query SEC Filings** - Search by ticker, CIK, form type, and date range
- **Entity Mapping** - Resolve tickers, CIKs, CUSIPs, and company names
- **XBRL Extraction** - Extract structured financial data from filings
- **Type-Safe Responses** - Immutable value objects with Dry::Struct
- **Flexible Configuration** - YAML files and environment variables

### Coming in v1.0.0 🚧

- **Production-Grade Error Handling** - TransientError/PermanentError hierarchy with automatic retry
- **Fluent Query Builder** - ActiveRecord-style chainable query DSL
- **Automatic Pagination** - Memory-efficient iteration over large result sets
- **Real-Time Streaming** - WebSocket notifications for new filings (<2 min latency)
- **Intelligent Rate Limiting** - Proactive throttling and request queueing
- **XBRL Validation** - Heuristic validation for US GAAP and IFRS taxonomies
- **Observability Hooks** - Production monitoring with structured logging and metrics
- **Comprehensive Documentation** - 100% YARD coverage with usage examples

## Installation

Add to your application's Gemfile:

```bash
bundle add sec_api
```

Or install directly:

```bash
gem install sec_api
```

## Quick Start

### 1. Configuration

**Option A: YAML Configuration**

Create `config/secapi.yml`:

```yaml
api_key: your_api_key_here
base_url: https://api.sec-api.io  # optional, defaults to production
retry_max_attempts: 5              # optional
retry_initial_delay: 1.0           # optional (seconds)
retry_max_delay: 60.0              # optional (seconds)
```

**Option B: Environment Variables**

```bash
export SECAPI_API_KEY=your_api_key_here
```

Get your API key from [sec-api.io](https://sec-api.io).

### 2. Basic Usage

```ruby
require 'sec_api'

# Initialize client (auto-loads configuration)
client = SecApi::Client.new

# Query filings by ticker
filings = client.query.ticker("AAPL").search
filings.each do |filing|
  puts "#{filing.form_type} filed on #{filing.filed_at}"
end

# Resolve ticker to CIK
entity = client.mapping.ticker("AAPL")
puts "CIK: #{entity.cik}, Name: #{entity.name}"

# Extract XBRL financial data
xbrl_data = client.xbrl.to_json(filing_url)
puts "Revenue: #{xbrl_data.financials.revenue}"
```

## Usage Examples

### Query Builder (Coming in v1.0.0)

```ruby
# Simple ticker query
filings = client.query
  .ticker("AAPL")
  .form_type("10-K")
  .search

# Date range and multiple form types
filings = client.query
  .ticker("TSLA")
  .form_type("10-K", "10-Q")
  .date_range(from: "2020-01-01", to: "2023-12-31")
  .limit(50)
  .search

# Full-text search
filings = client.query
  .ticker("META")
  .search_text("artificial intelligence")
  .search
```

### Automatic Pagination (Coming in v1.0.0)

```ruby
# First page only (default)
filings = client.query.ticker("AAPL").search
puts "First page: #{filings.count} filings"

# Manual pagination
next_page = filings.fetch_next_page if filings.has_more?

# Automatic pagination for backfills
client.query
  .ticker("AAPL")
  .date_range(from: 5.years.ago, to: Date.today)
  .auto_paginate
  .each do |filing|
    # Process thousands of filings with constant memory usage
    process_filing(filing)
  end
```

### Entity Mapping

```ruby
# Ticker to CIK
entity = client.mapping.ticker("AAPL")
# => #<SecApi::Entity cik="0000320193" ticker="AAPL" name="Apple Inc.">

# CIK to ticker
entity = client.mapping.cik("0000320193")

# CUSIP lookup
entity = client.mapping.cusip("037833100")

# Company name search
entity = client.mapping.name("Apple Inc.")
```

### XBRL Data Extraction

```ruby
# Extract complete XBRL data
xbrl_data = client.xbrl.to_json(filing_url)

# Access financial metrics
puts xbrl_data.financials.revenue
puts xbrl_data.financials.assets
puts xbrl_data.financials.liabilities
puts xbrl_data.financials.equity

# Check validation results (v1.0.0)
if xbrl_data.validation_results.passed?
  puts "Data validated successfully"
end
```

### Real-Time Filing Notifications (Coming in v1.0.0)

```ruby
# Subscribe to all filings
client.stream.subscribe do |filing|
  puts "New filing: #{filing.ticker} - #{filing.form_type}"
  # Process immediately or enqueue background job
end

# Filter by ticker and form type
client.stream.subscribe(
  tickers: ["AAPL", "TSLA"],
  form_types: ["10-K", "8-K"]
) do |filing|
  ProcessFilingJob.perform_later(filing.accession_no)
end
```

### Error Handling (v1.0.0)

```ruby
begin
  filings = client.query.ticker("AAPL").search
rescue SecApi::RateLimitError => e
  # Automatically retried with exponential backoff
  # Only raised after max retries exhausted
  puts "Rate limited: #{e.message}"
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

### Observability (Coming in v1.0.0)

```ruby
# Configure instrumentation callbacks
SecApi::Config.configure do |config|
  config.on_request = ->(env) {
    logger.info("API Request", request_id: env.request_id, url: env.url)
  }

  config.on_response = ->(env) {
    StatsD.timing("sec_api.request.duration", env.duration_ms)
  }

  config.on_retry = ->(env) {
    logger.warn("Retry attempt", request_id: env.request_id, attempt: env.retry_count)
  }

  config.on_rate_limit = ->(state) {
    logger.warn("Rate limit", remaining: state.remaining, reset_at: state.reset_at)
  }
end
```

## Architecture

### Client → Proxy Pattern

```ruby
SecApi::Client
├── .query      # Query API proxy
├── .mapping    # Mapping API proxy (ticker/CIK resolution)
├── .extractor  # Extractor API proxy
└── .xbrl       # XBRL API proxy (financial data)
```

### Exception Hierarchy

```
SecApi::Error (base)
├── TransientError (automatic retry)
│   ├── RateLimitError
│   ├── ServerError (5xx)
│   └── NetworkError
└── PermanentError (fail immediately)
    ├── AuthenticationError (401)
    ├── NotFoundError (404)
    ├── ValidationError
    └── ConfigurationError
```

### Middleware Stack (v1.0.0)

```
Request → Instrumentation → Retry → RateLimiter → ErrorHandler → Adapter → sec-api.io
```

## Configuration Options

All options can be set via YAML or environment variables:

| Option | YAML Key | Env Variable | Default | Description |
|--------|----------|--------------|---------|-------------|
| API Key | `api_key` | `SECAPI_API_KEY` | _(required)_ | Your sec-api.io API key |
| Base URL | `base_url` | `SECAPI_BASE_URL` | `https://api.sec-api.io` | API base URL |
| Max Retries | `retry_max_attempts` | `SECAPI_RETRY_MAX_ATTEMPTS` | `5` | Maximum retry attempts |
| Initial Delay | `retry_initial_delay` | `SECAPI_RETRY_INITIAL_DELAY` | `1.0` | Initial retry delay (seconds) |
| Max Delay | `retry_max_delay` | `SECAPI_RETRY_MAX_DELAY` | `60` | Maximum retry delay (seconds) |
| Backoff Factor | `retry_backoff_factor` | `SECAPI_RETRY_BACKOFF_FACTOR` | `2` | Exponential backoff multiplier |
| Request Timeout | `request_timeout` | `SECAPI_REQUEST_TIMEOUT` | `30` | HTTP request timeout (seconds) |
| Rate Limit Threshold | `rate_limit_threshold` | `SECAPI_RATE_LIMIT_THRESHOLD` | `0.1` | Throttle when <10% quota remains |

## Requirements

- **Ruby:** 3.1.0 or higher
- **Dependencies:**
  - `faraday` - HTTP client
  - `faraday-retry` - Automatic retry middleware
  - `anyway_config` - Configuration management
  - `dry-struct` - Immutable value objects
  - `faye-websocket` - WebSocket client for streaming API
  - `eventmachine` - Event-driven I/O (required by faye-websocket)

## Development

### Setup

```bash
git clone https://github.com/ljuti/sec_api.git
cd sec_api
bin/setup
```

### Testing

```bash
# Run all tests
bundle exec rspec

# Run with coverage
bundle exec rspec --format documentation

# Linting
bundle exec standardrb
```

### Interactive Console

```bash
bin/console

# Inside console
client = SecApi::Client.new
client.query.ticker("AAPL").search
```

See [Development Guide](docs/development-guide.md) for detailed setup instructions.

## Documentation

- **[Project Overview](docs/project-overview.md)** - Executive summary and roadmap
- **[Source Tree Analysis](docs/source-tree-analysis.md)** - Code organization guide
- **[Development Guide](docs/development-guide.md)** - Setup and workflow
- **[Product Requirements](docs/../_bmad-output/planning-artifacts/prd.md)** - Complete requirements
- **[Architecture](docs/../_bmad-output/planning-artifacts/architecture.md)** - Technical decisions
- **[Epics & Stories](docs/../_bmad-output/planning-artifacts/epics.md)** - Implementation roadmap

### YARD Documentation (Coming in v1.0.0)

```bash
bundle exec yard doc
open doc/index.html
```

## Roadmap

### v0.1.0 (Current)
- ✅ Basic query, search, mapping, extractor endpoints
- ✅ Configuration via anyway_config
- ✅ Immutable value objects (Dry::Struct)

### v1.0.0 (In Progress)
- 🚧 Production-grade error handling and retry logic
- 🚧 Fluent query builder DSL
- 🚧 Automatic pagination
- 🚧 XBRL extraction with validation
- 🚧 Real-time streaming API (WebSocket)
- 🚧 Intelligent rate limiting
- 🚧 Observability hooks
- 🚧 100% YARD documentation coverage
- 🚧 Migration guide from v0.1.0

See [Epics & Stories](docs/../_bmad-output/planning-artifacts/epics.md) for detailed implementation plan.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/ljuti/sec_api.

### Development Workflow

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/my-feature`)
3. Write tests for your changes
4. Ensure tests pass and linter is clean (`bundle exec rspec && bundle exec standardrb`)
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

**Status:** Active development - transitioning from v0.1.0 to v1.0.0

For brownfield context and AI-assisted development, see the complete [documentation index](docs/index.md).
