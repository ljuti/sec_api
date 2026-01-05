# sec_api - Development Guide

**Generated:** 2026-01-05

## Prerequisites

### Required
- **Ruby:** 3.1.0 or higher (project uses 3.2.3)
- **Bundler:** Latest version
- **Git:** For version control

### Optional
- **sec-api.io API Key:** Required for live API testing (get from https://sec-api.io)

## Initial Setup

### 1. Clone and Install Dependencies

```bash
# Clone the repository
git clone https://github.com/ljuti/sec_api.git
cd sec_api

# Run setup script
bin/setup

# Or manual setup:
bundle install
```

### 2. Configuration

Create a local configuration file:

```bash
# Copy example configuration
cp config/secapi.yml.example config/secapi.local.yml

# Edit with your API key
# config/secapi.local.yml
api_key: YOUR_API_KEY_HERE
```

**Environment Variable Alternative:**

```bash
export SECAPI_API_KEY=your_api_key_here
```

**Note:** `config/secapi.local.yml` is gitignored and won't be committed.

## Development Workflow

### Interactive Console

```bash
bin/console

# Inside console:
client = SecApi::Client.new
client.query.ticker("AAPL").search
# => SecApi::Filings collection
```

### Running Tests

```bash
# Run all tests
bundle exec rspec

# Run specific test file
bundle exec rspec spec/sec_api/client_spec.rb

# Run with coverage report
bundle exec rspec --format documentation
```

### Linting

```bash
# Run Standard Ruby linter
bundle exec standardrb

# Auto-fix issues
bundle exec standardrb --fix
```

### Building the Gem

```bash
# Build gem file
gem build sec_api.gemspec

# Install locally for testing
gem install sec_api-0.1.0.gem
```

## Project Structure

See [Source Tree Analysis](./source-tree-analysis.md) for complete directory structure.

**Key Directories:**
- `lib/sec_api/` - Main library code
- `spec/` - RSpec tests
- `config/` - Configuration files
- `_bmad-output/` - Planning artifacts (PRD, Architecture, Epics)

## Testing Strategy

### VCR Cassettes

The project uses VCR to record HTTP interactions for deterministic, offline-runnable tests.

**Recording New Cassettes:**

```ruby
# spec/sec_api/query_spec.rb
VCR.use_cassette("query_proxy/ticker_search") do
  client.query.ticker("AAPL").search
end
```

**Cassette Organization:**
- `spec/fixtures/vcr_cassettes/query_proxy/` - Query API cassettes
- `spec/fixtures/vcr_cassettes/mapping_proxy/` - Mapping API cassettes

### Running Tests Without API Key

VCR cassettes allow tests to run without a live API connection:

```bash
# Tests use recorded cassettes
bundle exec rspec

# No API key needed if cassettes exist
```

### Re-recording Cassettes

```bash
# Delete old cassettes
rm -rf spec/fixtures/vcr_cassettes/

# Run tests with live API (requires API key)
SECAPI_API_KEY=your_key bundle exec rspec

# New cassettes will be recorded
```

## Code Style

### Standard Ruby

The project follows [Standard Ruby](https://github.com/testdouble/standard) style guide.

**Enforced by:** `bundle exec standardrb`

**Key Rules:**
- 2-space indentation
- No trailing whitespace
- snake_case for methods and variables
- PascalCase for classes and modules
- SCREAMING_SNAKE_CASE for constants

### Naming Conventions

```ruby
# Classes and Modules
class SecApi::Client
module SecApi::Errors

# Methods and Variables
def query_filings
  api_key = config.api_key

# Constants
DEFAULT_MAX_RETRIES = 5
RETRYABLE_STATUS_CODES = [429, 500, 502, 503, 504]
```

## Common Development Tasks

### Adding a New API Endpoint

1. **Create proxy class:** `lib/sec_api/my_endpoint.rb`
2. **Wire to Client:** Add delegator in `lib/sec_api/client.rb`
3. **Add response object:** `lib/sec_api/objects/my_response.rb` (Dry::Struct)
4. **Write tests:** `spec/sec_api/my_endpoint_spec.rb`
5. **Record VCR cassette:** Run tests with live API

### Adding New Error Type

1. **Create error class:** `lib/sec_api/errors/my_error.rb`
2. **Inherit from TransientError or PermanentError:**

```ruby
module SecApi
  class MyError < TransientError  # or PermanentError
  end
end
```

3. **Add to error handler middleware:** `lib/sec_api/middleware/error_handler.rb`
4. **Write tests:** `spec/sec_api/errors/my_error_spec.rb`

### Adding Configuration Option

1. **Update config class:** `lib/sec_api/config.rb`

```ruby
class Config < Anyway::Config
  attr_config :my_new_option,
              :existing_option
end
```

2. **Add to YAML:** `config/secapi.yml`
3. **Document in README**

## CI/CD (Planned for v1.0.0)

**GitHub Actions workflows:**
- `.github/workflows/ci.yml` - Run tests, linting, coverage check
- `.github/workflows/release.yml` - Publish gem to RubyGems

## Release Process (Planned for v1.0.0)

1. **Update version:** `lib/sec_api/version.rb`
2. **Update CHANGELOG:** Add release notes
3. **Commit changes:** `git commit -m "Release v1.0.0"`
4. **Tag release:** `git tag v1.0.0`
5. **Push to GitHub:** `git push && git push --tags`
6. **GitHub Actions:** Automatically builds and publishes gem

## Documentation

### YARD Documentation

Generate YARD docs:

```bash
bundle exec yard doc

# View locally
open doc/index.html
```

**YARD Coverage Goal:** 100% for public APIs (v1.0.0 requirement)

### Updating Planning Documents

Planning artifacts are in `_bmad-output/planning-artifacts/`:
- **PRD:** Product requirements
- **Architecture:** Architectural decisions
- **Epics:** Story breakdown

**These are living documents** - update as the project evolves.

## Troubleshooting

### Bundle Install Fails

```bash
# Try updating bundler
gem install bundler
bundle update
```

### Tests Fail with VCR Errors

```bash
# Re-record cassettes with live API
rm -rf spec/fixtures/vcr_cassettes/
SECAPI_API_KEY=your_key bundle exec rspec
```

### Configuration Not Loading

Check configuration priority:
1. Environment variables (`SECAPI_*`)
2. Local YAML (`config/secapi.local.yml`)
3. Default YAML (`config/secapi.yml`)

## Additional Resources

- **[Project Overview](./project-overview.md)** - High-level project context
- **[Source Tree Analysis](./source-tree-analysis.md)** - Code organization
- **[README](../README.md)** - Quick start and usage
- **[PRD](../_bmad-output/planning-artifacts/prd.md)** - Complete requirements
- **[Architecture](../_bmad-output/planning-artifacts/architecture.md)** - Technical decisions
- **[Epics](../_bmad-output/planning-artifacts/epics.md)** - Implementation stories
