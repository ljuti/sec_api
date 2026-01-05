# Migration Guide: v0.1.0 → v1.0.0

This guide documents breaking changes when upgrading from `sec_api` v0.1.0 to v1.0.0 and provides migration examples.

## Overview of Breaking Changes

v1.0.0 standardizes all API responses to return **strongly-typed, immutable objects** instead of raw hashes. This ensures thread safety, improves IDE support, and provides a consistent API surface.

**Affected endpoints:**
- Mapping endpoints (ticker, cik, cusip, name)
- Extractor endpoint (extract)
- FulltextResults collection (now Enumerable)

## Breaking Change #1: Mapping Methods Return Entity Objects

### What Changed

All mapping methods now return `SecApi::Entity` objects instead of raw hashes.

**Affected methods:**
- `client.mapping.ticker(symbol)`
- `client.mapping.cik(cik_number)`
- `client.mapping.cusip(cusip_id)`
- `client.mapping.name(company_name)`

### Migration Example

**v0.1.0 - Returns Hash:**
```ruby
client = SecApi::Client.new(api_key: "your_key")
entity_data = client.mapping.ticker("AAPL")

# Hash access with string keys
cik = entity_data["cik"]           # => "0000320193"
ticker = entity_data["ticker"]     # => "AAPL"
name = entity_data["name"]         # => "Apple Inc."
```

**v1.0.0 - Returns Entity Object:**
```ruby
client = SecApi::Client.new(api_key: "your_key")
entity = client.mapping.ticker("AAPL")

# Method access (typed attributes)
cik = entity.cik           # => "0000320193"
ticker = entity.ticker     # => "AAPL"
name = entity.name         # => "Apple Inc."

# Hash access NO LONGER WORKS
entity["cik"]  # => NoMethodError: undefined method `[]' for SecApi::Entity
```

### Migration Steps

1. **Replace hash bracket notation with method calls:**
   ```ruby
   # BEFORE
   entity_data["cik"]

   # AFTER
   entity.cik
   ```

2. **Update type checks if any:**
   ```ruby
   # BEFORE
   if entity_data.is_a?(Hash)

   # AFTER
   if entity.is_a?(SecApi::Entity)
   ```

3. **Immutability note:** Entity objects are frozen and cannot be modified:
   ```ruby
   entity.cik = "new_value"  # => FrozenError: can't modify frozen SecApi::Entity
   ```

## Breaking Change #2: Extractor Returns ExtractedData Objects

### What Changed

The `extract` method now returns `SecApi::ExtractedData` objects instead of raw hashes.

**Affected methods:**
- `client.extractor.extract(filing_url)`

### Migration Example

**v0.1.0 - Returns Hash:**
```ruby
client = SecApi::Client.new(api_key: "your_key")
filing_url = "https://www.sec.gov/Archives/edgar/data/320193/..."

extracted = client.extractor.extract(filing_url)

# Hash access
text = extracted["text"]
sections = extracted["sections"]
metadata = extracted["metadata"]
```

**v1.0.0 - Returns ExtractedData Object:**
```ruby
client = SecApi::Client.new(api_key: "your_key")
filing_url = "https://www.sec.gov/Archives/edgar/data/320193/..."

extracted = client.extractor.extract(filing_url)

# Method access (typed attributes)
text = extracted.text              # => "Full extracted text..."
sections = extracted.sections      # => { risk_factors: "...", financials: "..." }
metadata = extracted.metadata      # => { source_url: "...", form_type: "10-K" }

# Hash access NO LONGER WORKS
extracted["text"]  # => NoMethodError: undefined method `[]' for SecApi::ExtractedData
```

### Migration Steps

1. **Replace hash bracket notation with method calls:**
   ```ruby
   # BEFORE
   extracted["text"]
   extracted["sections"]["risk_factors"]

   # AFTER
   extracted.text
   extracted.sections[:risk_factors]  # Note: sections keys are symbols in v1.0.0
   ```

2. **Update type checks:**
   ```ruby
   # BEFORE
   if extracted.is_a?(Hash)

   # AFTER
   if extracted.is_a?(SecApi::ExtractedData)
   ```

3. **Handle optional attributes:**
   ```ruby
   # All attributes are optional (may be nil)
   if extracted.text
     process_text(extracted.text)
   end

   if extracted.sections
     risk_factors = extracted.sections[:risk_factors]
   end
   ```

## Breaking Change #3: FulltextResults is Enumerable

### What Changed

`SecApi::Collections::FulltextResults` now includes `Enumerable`, allowing direct iteration without calling `.fulltext_results` first.

### Migration Example

**v0.1.0 - Not Enumerable:**
```ruby
results = client.query.fulltext("merger acquisition")

# Must use .fulltext_results accessor
results.fulltext_results.each { |r| puts r.ticker }
results.fulltext_results.map(&:ticker)
results.fulltext_results.select { |r| r.form_type == "8-K" }
```

**v1.0.0 - Enumerable:**
```ruby
results = client.query.fulltext("merger acquisition")

# Direct iteration (Enumerable)
results.each { |r| puts r.ticker }
results.map(&:ticker)
results.select { |r| r.form_type == "8-K" }

# .fulltext_results accessor still works for backward compatibility
results.fulltext_results.each { |r| puts r.ticker }
```

### Migration Steps

1. **Simplify iteration (optional):**
   ```ruby
   # BEFORE (still works)
   results.fulltext_results.each { |r| ... }

   # AFTER (cleaner)
   results.each { |r| ... }
   ```

2. **Use Enumerable methods directly:**
   ```ruby
   # BEFORE
   results.fulltext_results.count
   results.fulltext_results.first(10)

   # AFTER
   results.count
   results.first(10)
   ```

## Thread Safety Improvements

All response objects in v1.0.0 are **immutable and thread-safe**:

```ruby
# Safe for concurrent usage (Sidekiq, background jobs, etc.)
entity = client.mapping.ticker("AAPL")

threads = 10.times.map do
  Thread.new do
    100.times { puts entity.cik }
  end
end

threads.each(&:join)  # No race conditions
```

## IDE Autocomplete Benefits

With typed objects, your IDE can now provide accurate autocomplete:

```ruby
entity = client.mapping.ticker("AAPL")
entity.  # IDE shows: cik, ticker, name, exchange, sic, etc.

extracted = client.extractor.extract(filing_url)
extracted.  # IDE shows: text, sections, metadata
```

## Quick Reference: API Changes

| Endpoint | v0.1.0 Return Type | v1.0.0 Return Type | Migration |
|----------|-------------------|-------------------|-----------|
| `mapping.ticker()` | `Hash` | `Entity` | Use `.cik` instead of `["cik"]` |
| `mapping.cik()` | `Hash` | `Entity` | Use `.ticker` instead of `["ticker"]` |
| `mapping.cusip()` | `Hash` | `Entity` | Use `.name` instead of `["name"]` |
| `mapping.name()` | `Hash` | `Entity` | Use `.cik` instead of `["cik"]` |
| `extractor.extract()` | `Hash` | `ExtractedData` | Use `.text` instead of `["text"]` |
| `query.fulltext()` | `FulltextResults` (not Enumerable) | `FulltextResults` (Enumerable) | Use `.each` directly |

## Testing Your Migration

After migrating, verify your code works:

```ruby
# Test mapping endpoints
entity = client.mapping.ticker("AAPL")
raise unless entity.is_a?(SecApi::Entity)
raise unless entity.cik == "0000320193"

# Test extractor endpoint
extracted = client.extractor.extract(filing_url)
raise unless extracted.is_a?(SecApi::ExtractedData)
raise unless extracted.text.is_a?(String) || extracted.text.nil?

# Test collections
results = client.query.fulltext("acquisition")
raise unless results.respond_to?(:each)
raise unless results.first.is_a?(SecApi::FulltextResult)
```

## Need Help?

- **GitHub Issues:** https://github.com/your-org/sec_api/issues
- **Documentation:** See README.md and inline YARD docs
- **Breaking Changes:** This migration guide documents all breaking changes

## Summary

v1.0.0 brings production-grade thread safety and a consistent, typed API surface. While hash access is no longer supported, the migration is straightforward: replace `["key"]` with `.key` for all mapping and extractor responses.
