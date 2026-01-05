# Enumerator Pattern Design for Auto-Pagination (Story 2.6)

## Problem Statement

Epic 2, Story 2.6 requires lazy auto-pagination for backfill operations spanning thousands of filings. The API has:
- Offset-based pagination (`from` parameter)
- Max 50 results per page
- Max 10,000 results per query
- Response format: `{ total: {...}, filings: [...] }`

**Goal:** Provide a Ruby Enumerator that fetches pages on-demand without loading all results into memory.

## Design Constraints

1. **Memory Efficiency:** Don't load 10,000 filings into memory at once
2. **Lazy Evaluation:** Only fetch next page when iterator needs it
3. **Ruby Idioms:** Use standard Enumerator pattern (supports `.each`, `.map`, `.select`, etc.)
4. **API Efficiency:** Minimize redundant requests
5. **Thread Safety:** Iterator must be thread-safe (Epic 1 requirement)
6. **Error Handling:** Retry transient errors (Epic 1 middleware handles this)

## API Contract Review

From sec-api.io documentation:
- Request: `POST /` with `{ query: "...", from: "0", size: "50" }`
- Response: `{ total: { value: 1250, relation: "eq" }, filings: [...] }`
- Pagination: Increment `from` by `size` (e.g., 0 → 50 → 100 → 150)
- Limit: Max 10,000 results per query

## Proposed Pattern: Lazy Enumerator with Page Fetching

### Architecture

```
QueryBuilder
  ├── .search()          → Filings collection (first page only, Story 2.5)
  └── .auto_paginate()   → AutoPaginatedFilings enumerator (all pages, Story 2.6)
                            └── Uses Ruby Enumerator::Lazy internally
```

### Implementation Strategy

**Option 1: Enumerator with fetch_next_page (RECOMMENDED)**

```ruby
class QueryBuilder
  def auto_paginate
    AutoPaginatedFilings.new(self)
  end
end

class AutoPaginatedFilings
  include Enumerable

  def initialize(query_builder)
    @query_builder = query_builder
    @current_offset = 0
    @page_size = 50
    @total_filings = nil  # Unknown until first page fetched
  end

  def each
    return enum_for(:each) unless block_given?

    loop do
      # Fetch current page
      page = fetch_page(@current_offset)

      # Update total on first fetch
      @total_filings ||= page.total_count

      # Yield each filing in the page
      page.each { |filing| yield filing }

      # Check if we're done
      break unless page.has_more?
      break if @current_offset + @page_size >= 10_000  # API max

      # Advance to next page
      @current_offset += @page_size
    end
  end

  private

  def fetch_page(offset)
    # Build request with current offset
    payload = @query_builder.build_payload(from: offset, size: @page_size)

    # Execute request (retry middleware handles transient errors)
    response = @query_builder.client.connection.post("/", payload)

    # Return Filings collection for this page
    Collections::Filings.new(response.body)
  end
end
```

**Option 2: Enumerator::Lazy (More Ruby-idiomatic)**

```ruby
class QueryBuilder
  def auto_paginate
    Enumerator.new do |yielder|
      offset = 0
      page_size = 50

      loop do
        # Fetch page
        payload = build_payload(from: offset, size: page_size)
        response = @client.connection.post("/", payload)
        page = Collections::Filings.new(response.body)

        # Yield each filing
        page.each { |filing| yielder << filing }

        # Check if done
        break unless page.has_more?
        break if offset + page_size >= 10_000

        offset += page_size
      end
    end.lazy  # Lazy evaluation - only fetches when needed
  end
end
```

**Comparison:**

| Aspect | Option 1 (Class) | Option 2 (Enumerator.new) |
|--------|------------------|---------------------------|
| Code complexity | Medium | Low |
| Testability | High (can mock AutoPaginatedFilings) | Medium (Enumerator harder to mock) |
| Memory efficiency | Excellent | Excellent |
| Ruby idioms | Good (include Enumerable) | Excellent (native Enumerator) |
| Thread safety | Needs Mutex on state | Immutable state per iterator |
| Debugging | Easier (class with state) | Harder (closure state) |

**Recommendation:** Option 2 (Enumerator.new) for Story 2.6 because:
- More Ruby-idiomatic
- Less code to maintain
- Automatically thread-safe (each call creates new Enumerator)
- Lazy evaluation built-in

We can add Option 1 later if we need more control or testability.

## Usage Examples

### Basic Auto-Pagination

```ruby
client = SecApi::Client.new
filings = client.query
  .ticker("AAPL")
  .form_type("10-K")
  .date_range(from: "2020-01-01", to: "2023-12-31")
  .auto_paginate

# Lazy iteration - fetches pages as needed
filings.each do |filing|
  puts "#{filing.ticker}: #{filing.filed_at}"
  # Only fetches next page when current page is exhausted
end
```

### With Lazy Enumerator Methods

```ruby
# Take only first 100 filings (fetches 2 pages max)
filings.take(100).each { |f| process(f) }

# Find first match (stops iterating after finding)
filing = filings.find { |f| f.form_type == "10-K/A" }

# Map and filter (still lazy)
tickers = filings
  .select { |f| f.form_type == "10-K" }
  .map(&:ticker)
  .uniq
```

### Memory-Efficient Backfill

```ruby
# Process 5,000 filings without loading all into memory
client.query
  .ticker("TSLA")
  .date_range(from: "2015-01-01", to: "2024-12-31")
  .auto_paginate
  .each_slice(100) do |batch|
    # Process in batches of 100
    batch.each { |filing| extract_and_save(filing) }
  end
```

## Implementation Details

### QueryBuilder Changes

```ruby
class QueryBuilder
  # Existing terminal method (Story 2.5)
  def search
    payload = build_payload(from: 0, size: 50)
    response = @client.connection.post("/", payload)
    Collections::Filings.new(response.body)
  end

  # NEW: Auto-pagination terminal method (Story 2.6)
  def auto_paginate
    Enumerator.new do |yielder|
      offset = 0
      page_size = 50

      loop do
        payload = build_payload(from: offset, size: page_size)
        response = @client.connection.post("/", payload)
        page = Collections::Filings.new(response.body)

        page.each { |filing| yielder << filing }

        break unless page.has_more?
        break if offset + page_size >= 10_000  # API max

        offset += page_size
      end
    end.lazy
  end

  private

  def build_payload(from:, size:)
    {
      query: to_lucene,
      from: from.to_s,
      size: size.to_s,
      sort: @sort_config
    }
  end
end
```

### Filings Collection Enhancement

The `Collections::Filings` class needs pagination metadata:

```ruby
class Collections::Filings
  include Enumerable

  attr_reader :total_count, :filings

  def initialize(response)
    @total = response["total"] || response[:total]
    @total_count = @total["value"] || @total[:value]
    @total_relation = @total["relation"] || @total[:relation]
    @filings = (response["filings"] || response[:filings] || []).map do |data|
      Filing.new(data)
    end
    @filings.freeze
  end

  def each(&block)
    @filings.each(&block)
  end

  def has_more?
    # If relation is "gte", there are definitely more results
    # If we got a full page (50), there might be more
    @total_relation == "gte" || @filings.size == 50
  end

  def size
    @filings.size
  end

  def count
    @total_count
  end
end
```

## Error Handling

Auto-pagination leverages Epic 1's retry middleware:
- **TransientError** (network, 5xx, 429): Automatically retried with exponential backoff
- **PermanentError** (401, 404, validation): Raised immediately, iteration stops

```ruby
begin
  client.query.ticker("AAPL").auto_paginate.each do |filing|
    process(filing)
  end
rescue SecApi::AuthenticationError => e
  # Permanent error - fix API key
  logger.error("Authentication failed: #{e.message}")
rescue SecApi::TransientError => e
  # Should never reach here - retry middleware handles it
  logger.error("Retry exhausted: #{e.message}")
end
```

## Thread Safety

Each call to `.auto_paginate` creates a new Enumerator with its own closure state:

```ruby
# Thread-safe - each thread gets independent iterator
threads = 10.times.map do |i|
  Thread.new do
    client.query.ticker("AAPL").auto_paginate.take(100).each do |filing|
      puts "Thread #{i}: #{filing.ticker}"
    end
  end
end
threads.each(&:join)
```

**Why it's thread-safe:**
- No shared mutable state
- Each Enumerator has its own `offset` variable in closure
- Faraday connection pool handles concurrent requests (Epic 1)
- Filing objects are immutable (Dry::Struct from Epic 1)

## Performance Characteristics

**Memory:**
- O(page_size) = O(50) filings in memory at a time
- Total memory constant regardless of result set size

**Network:**
- N requests for N pages
- Each request: 50 filings
- Total requests for 5,000 filings: 100 requests

**Latency:**
- First filing: 1 request (same as `.search`)
- Filing 51: 2 requests (fetches page 2)
- Filing 101: 3 requests (fetches page 3)
- Total latency for 5,000 filings: ~100 requests × ~2s = ~200s (acceptable for backfill)

**Optimization Opportunities (Future):**
- Prefetch next page in background while processing current page
- Configurable page size (currently hardcoded to 50)
- Parallel page fetching for multiple ticker backfills

## Testing Strategy

### Unit Tests (QueryBuilder)

```ruby
RSpec.describe QueryBuilder do
  describe "#auto_paginate" do
    it "returns an Enumerator" do
      builder = QueryBuilder.new(client)
      expect(builder.ticker("AAPL").auto_paginate).to be_a(Enumerator)
    end

    it "fetches multiple pages lazily" do
      # Stub 3 pages: 50, 50, 25 filings
      stub_page(0, 50, total: 125, has_more: true)
      stub_page(50, 50, total: 125, has_more: true)
      stub_page(100, 25, total: 125, has_more: false)

      filings = builder.ticker("AAPL").auto_paginate.to_a
      expect(filings.size).to eq(125)
    end

    it "stops at 10,000 filing API limit" do
      # Even if total > 10,000, stop at 10,000
      stub_page(0, 50, total: 15_000, has_more: true)
      # ... stub pages up to offset 9,950

      filings = builder.ticker("AAPL").auto_paginate.to_a
      expect(filings.size).to eq(10_000)
    end

    it "supports lazy operations" do
      stub_page(0, 50, total: 500, has_more: true)

      # Only fetches first page (take(10) stops early)
      filings = builder.ticker("AAPL").auto_paginate.take(10).to_a
      expect(filings.size).to eq(10)
      expect(client.connection).to have_received(:post).once  # Only 1 request
    end
  end
end
```

### Integration Tests

```ruby
RSpec.describe "Auto-pagination integration" do
  it "handles multi-page backfill" do
    client = SecApi::Client.new

    filings = client.query
      .ticker("AAPL")
      .date_range(from: "2023-01-01", to: "2023-12-31")
      .auto_paginate
      .to_a

    expect(filings).to all(be_a(Filing))
    expect(filings.map(&:ticker).uniq).to eq(["AAPL"])
  end

  it "retries transient errors during pagination" do
    # First page succeeds, second page fails with 503, then succeeds
    # Retry middleware should handle transparently

    # ... VCR cassette or stub setup
  end
end
```

## 10,000 Result Limit Strategy

For queries returning >10,000 results, guide users to chunk by date:

```ruby
# Helper method (could be added in Epic 2 or later)
def backfill_by_year(ticker, start_year, end_year)
  (start_year..end_year).each do |year|
    client.query
      .ticker(ticker)
      .date_range(from: "#{year}-01-01", to: "#{year}-12-31")
      .auto_paginate
      .each { |filing| process(filing) }
  end
end

# Usage
backfill_by_year("AAPL", 2010, 2024)  # Chunks into 15 queries (1 per year)
```

**Documentation Note:** Warn users in YARD docs:
```ruby
# @note The sec-api.io API limits queries to 10,000 results. For larger
#   datasets, split your query into smaller date ranges.
# @example Multi-year backfill with date chunking
#   (2010..2024).each do |year|
#     client.query.ticker("AAPL")
#       .date_range(from: "#{year}-01-01", to: "#{year}-12-31")
#       .auto_paginate.each { |filing| process(filing) }
#   end
```

## Summary

**Pattern:** Enumerator.new with lazy evaluation
**Memory:** O(50) constant per iterator
**Thread Safety:** ✅ Each call creates independent Enumerator
**Error Handling:** ✅ Leverages Epic 1 retry middleware
**API Efficiency:** ✅ Only fetches pages as needed
**Ruby Idioms:** ✅ Works with `.map`, `.select`, `.take`, etc.

**Implementation Complexity:** Low (< 20 lines in QueryBuilder)
**Test Coverage:** Medium (stub pagination responses, test lazy behavior)

**Ready for Story 2.6 implementation:** ✅

---

**Design Decision Log:**

| Decision | Rationale |
|----------|-----------|
| Enumerator.new over custom class | More idiomatic Ruby, less code, auto thread-safe |
| Lazy evaluation (.lazy) | Memory efficiency, supports Ruby Enumerable methods |
| Hardcode page_size to 50 | API max, no benefit to smaller pages |
| Stop at 10,000 limit | API constraint, document chunking strategy |
| No background prefetching | Keep it simple for Story 2.6, optimize later if needed |
| Leverage Epic 1 retry middleware | DRY principle, automatic transient error recovery |

---

**Next Steps for Story 2.6:**
1. Implement `auto_paginate` method in QueryBuilder
2. Add `has_more?` method to Filings collection
3. Write unit tests for lazy pagination behavior
4. Write integration tests with multi-page VCR cassettes
5. Update YARD documentation with 10,000 limit warning
6. Add usage examples to README
