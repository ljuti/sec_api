# SecApi Usage Examples

This directory contains working code examples demonstrating common usage patterns for the `sec_api` Ruby gem.

## Prerequisites

1. Install the gem:
   ```bash
   gem install sec_api
   # or add to your Gemfile
   gem 'sec_api', '~> 1.0'
   ```

2. Set your API key:
   ```bash
   export SECAPI_API_KEY="your_api_key_here"
   ```

   Get your API key from [sec-api.io](https://sec-api.io)

## Available Examples

| File | Description |
|------|-------------|
| [query_builder.rb](query_builder.rb) | Query filings by ticker, CIK, form type, date range, and full-text search |
| [backfill_filings.rb](backfill_filings.rb) | Multi-year backfill with auto-pagination and progress logging |
| [streaming_notifications.rb](streaming_notifications.rb) | Real-time WebSocket notifications with filters and callbacks |
| [instrumentation.rb](instrumentation.rb) | Logging, metrics, and filing journey tracking |

## Running Examples

Each example is self-contained and can be run directly:

```bash
ruby docs/examples/query_builder.rb
ruby docs/examples/backfill_filings.rb
ruby docs/examples/streaming_notifications.rb
ruby docs/examples/instrumentation.rb
```

## Example Structure

Each example file follows a consistent structure:
- Header comments explaining what it demonstrates
- Prerequisites and usage instructions
- Clearly commented code sections
- Copy-paste ready patterns

## API Documentation

For detailed API reference, see the YARD documentation:

```bash
bundle exec yard doc
open doc/index.html
```

Or read the [migration guide](../migration-guide-v1.md) for comprehensive API patterns.
