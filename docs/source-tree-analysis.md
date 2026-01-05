# sec_api - Source Tree Analysis

**Generated:** 2026-01-05
**Project Root:** `/Users/ljuti/Code/projects/metalsmoney/ruby/sec_api`

## Directory Structure with Annotations

```
sec_api/
├── .github/
│   └── workflows/           # CI/CD workflows (planned for v1.0)
├── .git/                    # Git repository
├── .ruby-lsp/              # Ruby LSP cache
├── _bmad/                  # BMAD framework installation
│   ├── core/               # Core BMAD modules
│   └── bmm/                # BMM (BMAD Methodology Manager) modules
├── _bmad-output/           # BMAD planning artifacts
│   ├── planning-artifacts/  # PRD, Architecture, Epics documents
│   └── implementation-artifacts/  # (future: sprint status, stories)
├── bin/
│   ├── console             # Interactive IRB console for development
│   └── setup               # Setup script for dependencies
├── config/
│   └── secapi.yml          # Configuration file (API key, settings)
├── docs/                   # PROJECT DOCUMENTATION (this directory)
│   ├── project-overview.md  # Project overview (generated)
│   ├── source-tree-analysis.md  # This file
│   └── project-scan-report.json  # Workflow state tracking
├── lib/                    # MAIN LIBRARY CODE
│   ├── sec_api.rb          # Main entry point (requires all files)
│   └── sec_api/            # Library modules
│       ├── client.rb       # 🔑 Client entry point (delegates to proxies)
│       ├── config.rb       # Configuration management (anyway_config)
│       ├── version.rb      # Gem version constant
│       ├── collections/    # Collection objects (Enumerable wrappers)
│       │   ├── filings.rb  # Filings collection
│       │   └── fulltext_results.rb  # Full-text search results
│       ├── errors/         # 🔑 Exception hierarchy
│       │   ├── error.rb    # Base SecApi::Error
│       │   ├── transient_error.rb  # Retryable errors
│       │   ├── permanent_error.rb  # Non-retryable errors
│       │   ├── rate_limit_error.rb
│       │   ├── server_error.rb
│       │   ├── network_error.rb
│       │   ├── authentication_error.rb
│       │   ├── not_found_error.rb
│       │   ├── validation_error.rb
│       │   └── configuration_error.rb
│       ├── middleware/     # 🔑 Faraday middleware stack
│       │   └── error_handler.rb  # HTTP status → exception mapping
│       ├── objects/        # Value objects (Dry::Struct)
│       │   ├── filing.rb   # Filing metadata
│       │   ├── entity.rb   # Company/entity information
│       │   ├── fulltext_result.rb
│       │   ├── data_file.rb
│       │   └── document_format_file.rb
│       ├── query.rb        # Query API proxy
│       ├── mapping.rb      # Mapping API proxy (ticker/CIK resolution)
│       ├── extractor.rb    # Extractor API proxy
│       └── xbrl.rb         # XBRL API proxy
├── sig/                    # RBS type signatures (optional)
├── spec/                   # 🔑 RSPEC TESTS
│   ├── spec_helper.rb      # Test configuration
│   └── sec_api/            # Test files mirroring lib/ structure
├── .gitignore
├── .node-version           # Node version (for tooling)
├── .rspec                  # RSpec configuration
├── .rspec_status           # Test run status
├── .standard.yml           # Standard Ruby linter configuration
├── CHANGELOG.md            # Version history
├── CLAUDE.md               # Claude session notes
├── Gemfile                 # Gem dependencies
├── Gemfile.lock            # Locked dependency versions
├── LICENSE.txt             # MIT License
├── README.md               # Project README
├── Rakefile                # Rake tasks
└── sec_api.gemspec         # Gem specification
```

## Critical Directories Explained

### `/lib/sec_api/`  - Main Library Code

**Purpose:** Core gem functionality organized by technical layer

**Architecture Pattern:** Client → Proxy pattern with middleware stack

**Key Components:**
- **client.rb** - Main entry point, delegates to proxies
- **errors/** - Complete exception hierarchy (TransientError/PermanentError)
- **middleware/** - Faraday middleware (retry, rate limiting, error handling)
- **objects/** - Immutable value objects (Dry::Struct)
- **collections/** - Collection wrappers with Enumerable interface
- **Proxies:** query.rb, mapping.rb, extractor.rb, xbrl.rb

### `/spec/` - Test Suite

**Purpose:** RSpec tests mirroring lib/ structure

**Coverage:** >90% target for v1.0.0

**Testing Strategy:**
- VCR/WebMock cassettes for API integration tests
- Shared examples for cross-cutting behavior (retry, pagination, rate limiting)
- Unit tests for pure logic

### `/_bmad-output/planning-artifacts/` - Planning Documents

**Purpose:** Product requirements, architecture decisions, and epic breakdown

**Key Files:**
- **prd.md** - Product Requirements Document
- **architecture.md** - Architectural decisions and patterns
- **epics.md** - Epic and story breakdown for implementation

### `/config/` - Configuration Files

**Purpose:** YAML configuration and local overrides

**Files:**
- **secapi.yml** - Default configuration (API key, retry settings, etc.)
- **secapi.local.yml** (gitignored) - Local environment overrides

## Entry Points

### Main Entry Point
**File:** `lib/sec_api.rb`
**Purpose:** Requires all library files, provides top-level namespace

### Client Initialization
**File:** `lib/sec_api/client.rb`
**Usage:**
```ruby
client = SecApi::Client.new  # Auto-loads config from YAML
client.query                  # Query API proxy
client.mapping                # Mapping API proxy
client.extractor              # Extractor API proxy
client.xbrl                   # XBRL API proxy
```

### Development Console
**File:** `bin/console`
**Purpose:** Interactive IRB session with gem loaded for manual testing

## Code Organization Patterns

### Naming Conventions
- **Modules/Classes:** `SecApi::` namespace, PascalCase
- **Files:** snake_case matching class names
- **Methods:** snake_case (Ruby standard)
- **Constants:** SCREAMING_SNAKE_CASE

### File-to-Class Mapping
- `lib/sec_api/client.rb` → `SecApi::Client`
- `lib/sec_api/errors/rate_limit_error.rb` → `SecApi::RateLimitError`
- `lib/sec_api/objects/filing.rb` → `SecApi::Filing`

### Dependencies
- **External:** Faraday, anyway_config, dry-struct
- **Internal:** Client → Proxies → Middleware → HTTP API

## Integration Points

### External API
- **sec-api.io REST API** - All HTTP requests via Faraday
- **Base URL:** `https://api.sec-api.io` (configurable)
- **Authentication:** API key in headers

### Configuration
- **YAML files:** `config/secapi.yml`
- **Environment variables:** `SECAPI_*` prefix
- **Managed by:** anyway_config gem

### Testing
- **Framework:** RSpec
- **Mocking:** VCR/WebMock for HTTP requests
- **Linting:** Standard Ruby (standardrb)

## Future Directories (Planned for v1.0.0)

Based on the Architecture document, these directories will be added:

- `lib/sec_api/proxies/` - Organized proxy objects
- `lib/sec_api/middleware/retry_config.rb` - Enhanced retry configuration
- `lib/sec_api/middleware/rate_limiter.rb` - Rate limiting middleware
- `lib/sec_api/middleware/instrumentation.rb` - Observability hooks
- `spec/support/shared_examples/` - Shared test behavior
- `spec/fixtures/vcr_cassettes/` - VCR cassettes organized by proxy
- `docs/examples/` - Usage examples (query, backfill, streaming)
- `docs/migration-guide-v1.md` - v0.1.0 → v1.0.0 migration guide
