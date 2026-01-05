# sec_api - Project Overview

**Generated:** 2026-01-05
**Scan Level:** Quick
**Project Type:** Ruby Library (Gem)

## Executive Summary

sec_api is a production-grade Ruby client library for accessing SEC EDGAR filings through the sec-api.io API. The project is evolving from a basic v0.1.0 API wrapper into enterprise-level financial data infrastructure for commercial financial analysis platforms.

**Current State:** Active development, transitioning from v0.1.0 to v1.0.0
**Purpose:** Provide Ruby developers with reliable, resilient access to SEC filing data for financial analysis applications

## Project Classification

| Attribute | Value |
|-----------|-------|
| **Repository Type** | Monolith |
| **Project Type** | Library (Ruby Gem) |
| **Primary Language** | Ruby 3.2.3 |
| **Minimum Ruby** | 3.1.0+ |
| **Distribution** | RubyGems (rubygems.org) |
| **Architecture Pattern** | Client → Proxy pattern with middleware stack |

## Technology Stack

### Core Dependencies
- **faraday** - HTTP client with middleware capabilities
- **faraday-retry** - Automatic retry middleware
- **anyway_config** - Configuration management (YAML + environment variables)
- **dry-struct** - Immutable value objects for type-safe responses

### Development Dependencies
- **rspec** ~> 3.0 - Testing framework
- **standard** ~> 1.3 - Ruby linter (Standard Ruby style guide)
- **async-http-faraday** - Async HTTP support for concurrent requests

### Key Features (v1.0.0 Target)
- ✅ Configuration management with validation
- ✅ Exception hierarchy (TransientError/PermanentError)
- 🚧 Query builder DSL with fluent interface
- 🚧 Automatic pagination for large result sets
- 🚧 XBRL data extraction with validation
- 🚧 Real-time filing notifications (WebSocket streaming)
- 🚧 Rate limiting intelligence with proactive throttling
- 🚧 Production observability hooks

## Project Structure

```
sec_api/
├── lib/sec_api/          # Main library code
│   ├── client.rb         # Client entry point
│   ├── config.rb         # Configuration (anyway_config)
│   ├── errors/           # Exception hierarchy
│   ├── middleware/       # Faraday middleware (retry, rate limiting)
│   ├── collections/      # Collection objects (Filings, etc.)
│   └── objects/          # Value objects (Filing, Entity, etc.)
├── spec/                 # RSpec tests
├── config/               # Configuration files
└── _bmad-output/         # Planning artifacts (PRD, Architecture, Epics)
```

## Development Status

### Completed (v0.1.0)
- Basic query, search, mapping, and extractor endpoints
- Configuration via anyway_config
- Immutable value objects with Dry::Struct

### In Progress (v1.0.0)
- Production-grade error handling and retry logic
- Query builder DSL
- XBRL extraction with validation
- Real-time streaming API
- Rate limiting middleware
- Observability and instrumentation

## Links to Planning Documents

- **[PRD](../_bmad-output/planning-artifacts/prd.md)** - Complete product requirements
- **[Architecture](../_bmad-output/planning-artifacts/architecture.md)** - Architectural decisions and patterns
- **[Epics & Stories](../_bmad-output/planning-artifacts/epics.md)** - Implementation breakdown

## Links to Documentation

- [README](../README.md) - Project overview and usage
- [CHANGELOG](../CHANGELOG.md) - Version history
- [Source Tree Analysis](./source-tree-analysis.md) - Code organization
- [Development Guide](./development-guide.md) - Setup and development workflow
