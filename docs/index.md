# sec_api - Project Documentation Index

**Generated:** 2026-01-05
**Scan Level:** Quick
**Last Updated:** 2026-01-05T03:40:00Z

## Project Overview

**Name:** sec_api
**Type:** Ruby Library (Gem)
**Primary Language:** Ruby 3.2.3
**Architecture:** Client → Proxy pattern with Faraday middleware
**Status:** Active development (v0.1.0 → v1.0.0)

### Quick Reference

- **Purpose:** Production-grade Ruby client for SEC EDGAR filing data via sec-api.io API
- **Distribution:** RubyGems (rubygems.org)
- **License:** MIT
- **Repository:** https://github.com/ljuti/sec_api
- **Minimum Ruby Version:** 3.1.0+

### Technology Stack Summary

| Category | Technology | Version | Purpose |
|----------|-----------|---------|---------|
| **Language** | Ruby | 3.2.3 | Core language |
| **HTTP Client** | Faraday | Latest | HTTP requests with middleware |
| **Configuration** | anyway_config | Latest | YAML + env var config |
| **Value Objects** | dry-struct | Latest | Immutable, typed responses |
| **Testing** | RSpec | ~> 3.0 | Test framework |
| **Linting** | Standard Ruby | ~> 1.3 | Code style enforcement |

## Generated Documentation

### Core Documentation

- **[Project Overview](./project-overview.md)** - Executive summary, tech stack, project classification
- **[Source Tree Analysis](./source-tree-analysis.md)** - Directory structure, code organization, entry points
- **[Development Guide](./development-guide.md)** - Setup instructions, development workflow, testing guide

### Existing Documentation

- **[README](../README.md)** - Quick start, installation, basic usage
- **[CHANGELOG](../CHANGELOG.md)** - Version history and release notes

## Planning Artifacts

These comprehensive planning documents guide the v1.0.0 development:

### Solutioning Phase (Complete)

- **[Product Requirements Document (PRD)](../_bmad-output/planning-artifacts/prd.md)**
  *Complete requirements, user journeys, success criteria, domain-specific requirements*

- **[Architecture Decision Document](../_bmad-output/planning-artifacts/architecture.md)**
  *Architectural patterns, error handling strategy, retry/rate limiting, observability design*

- **[Epics & Stories](../_bmad-output/planning-artifacts/epics.md)**
  *8 epics broken down into implementation-ready user stories with acceptance criteria*

### Implementation Phase (Planned)

Sprint planning and story development will be tracked in:
- `_bmad-output/implementation-artifacts/sprint-status.yaml` _(To be generated)_
- `_bmad-output/implementation-artifacts/stories/` _(To be generated)_

## Project Architecture

### Repository Structure

```
sec_api/
├── lib/sec_api/          # Main library code (Client → Proxy pattern)
│   ├── client.rb         # Entry point
│   ├── errors/           # Exception hierarchy (TransientError/PermanentError)
│   ├── middleware/       # Faraday middleware (retry, rate limiting, observability)
│   ├── collections/      # Collection objects (Filings, etc.)
│   └── objects/          # Value objects (Filing, Entity, XbrlData)
├── spec/                 # RSpec tests (VCR cassettes, shared examples)
├── config/               # Configuration files (YAML + env vars)
└── _bmad-output/         # Planning artifacts
```

### Key Architectural Patterns

**Client → Proxy Pattern:**
```ruby
client = SecApi::Client.new
client.query      # Query API proxy
client.mapping    # Mapping API proxy (ticker/CIK resolution)
client.extractor  # Extractor API proxy
client.xbrl       # XBRL API proxy (financial data extraction)
```

**Exception Hierarchy:**
- `SecApi::Error` (base)
  - `TransientError` - Automatic retry (rate limits, network errors, server errors)
  - `PermanentError` - Fail immediately (authentication, not found, validation)

**Middleware Stack:**
```
Request → Instrumentation → Retry → RateLimiter → ErrorHandler → Adapter → sec-api.io
```

## Development Roadmap

### v0.1.0 (Current)
- ✅ Basic query, search, mapping, extractor endpoints
- ✅ Configuration via anyway_config
- ✅ Immutable value objects (Dry::Struct)
- ⚠️ Issues: Orphaned XBRL endpoint, inconsistent response wrapping, generic exceptions

### v1.0.0 (Target)
- 🚧 **Epic 1:** Foundation & production-grade error handling
  - Exception hierarchy (TransientError/PermanentError)
  - Enhanced retry middleware with exponential backoff
  - Thread-safe response objects
  - Wire up orphaned XBRL proxy

- 🚧 **Epic 2:** Query and search SEC filings
  - Fluent query builder DSL
  - Automatic pagination with `.auto_paginate`
  - International filing support (20-F, 40-F, 6-K)

- 🚧 **Epic 3:** Entity mapping and resolution
  - Ticker ↔ CIK resolution
  - CUSIP and company name lookups

- 🚧 **Epic 4:** XBRL data extraction with validation
  - Heuristic XBRL validation
  - US GAAP and IFRS taxonomy support

- 🚧 **Epic 5:** Rate limiting intelligence
  - Proactive header tracking
  - Automatic throttling and request queueing

- 🚧 **Epic 6:** Real-time filing notifications
  - WebSocket streaming API
  - Ticker/form-type filtering
  - <2 minute delivery latency

- 🚧 **Epic 7:** Observability and production monitoring
  - Instrumentation callbacks
  - Structured logging with correlation IDs
  - Metrics exposure

- 🚧 **Epic 8:** Documentation and developer experience
  - 100% YARD documentation coverage
  - Migration guide (v0.1.0 → v1.0.0)
  - Usage examples

## Getting Started

### For Developers Using This Gem

See **[README](../README.md)** for:
- Installation instructions
- Basic usage examples
- Configuration guide

### For Contributors

See **[Development Guide](./development-guide.md)** for:
- Setup instructions
- Development workflow
- Testing strategy
- Code style guidelines

### For Product/Technical Understanding

See **[PRD](../_bmad-output/planning-artifacts/prd.md)** for:
- Vision and success criteria
- User journeys
- Complete functional and non-functional requirements
- Domain-specific requirements (fintech, SEC filings)

See **[Architecture](../_bmad-output/planning-artifacts/architecture.md)** for:
- Architectural decisions and rationale
- Implementation patterns and consistency rules
- Error handling, retry, rate limiting strategies
- Observability and instrumentation design

## Key Features (Planned for v1.0.0)

### Production-Grade Infrastructure
- ✅ Automatic retry with exponential backoff (configurable)
- ✅ Exception hierarchy distinguishing transient vs permanent errors
- 🚧 Intelligent rate limiting with proactive throttling
- 🚧 Request queueing when rate limits are reached
- 🚧 Production observability hooks for monitoring tools

### Developer Experience
- 🚧 Fluent query builder DSL (ActiveRecord-style chaining)
- 🚧 Automatic pagination - memory-efficient backfill operations
- 🚧 Comprehensive YARD documentation (100% coverage)
- 🚧 VCR test fixtures for offline-runnable tests
- 🚧 Migration guide for v0.1.0 → v1.0.0 upgrade

### SEC Filing Coverage
- 🚧 Query by ticker, CIK, form type, date range
- 🚧 International filings (20-F, 40-F, 6-K for foreign/Canadian issuers)
- 🚧 Real-time filing notifications via WebSocket (<2 min latency)
- 🚧 XBRL extraction with validation (US GAAP + IFRS)
- 🚧 Entity mapping (ticker ↔ CIK, CUSIP, company name resolution)

## Workflow Integration

### For Brownfield PRD Creation

When planning new features for this project:

1. **Reference this documentation index** as the project context
2. **Use PRD as requirements baseline** for understanding existing scope
3. **Use Architecture for technical constraints** and established patterns
4. **Use Epics for implementation roadmap** and story structure

### For Implementation Work

When implementing stories from the Epics document:

1. **Follow architectural patterns** defined in Architecture document
2. **Use Development Guide** for setup and workflow
3. **Reference Source Tree Analysis** for code organization
4. **Maintain consistency** with established naming and structure patterns

## Contact & Support

- **Author:** Lauri Jutila
- **Email:** git@laurijutila.com
- **GitHub:** https://github.com/ljuti/sec_api
- **Issues:** https://github.com/ljuti/sec_api/issues

## License

MIT License - See [LICENSE.txt](../LICENSE.txt)

---

**Documentation Scan Details:**
- **Scan Type:** Initial Quick Scan
- **Scan Date:** 2026-01-05
- **Workflow:** BMAD document-project workflow
- **Status File:** [project-scan-report.json](./project-scan-report.json)
