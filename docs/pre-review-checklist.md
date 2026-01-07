# Pre-Review Checklist

Use this checklist before submitting code for review. These items were identified through Epic 3 and Epic 4 retrospectives as common issues caught in code review.

## Thread Safety

- [ ] **Immutable objects are frozen** - All Dry::Struct value objects should be deeply frozen
- [ ] **String attributes frozen** - Use `attribute&.freeze` for string attributes in value objects
- [ ] **Shared state protected** - Any state shared across requests uses Mutex or is immutable
- [ ] **No instance variable mutation** - Value objects don't mutate after construction

```ruby
# Good: Deep freeze in from_api
def self.from_api(data)
  new(
    statements_of_income: parse_statement(data["StatementsOfIncome"]).freeze,
    # ...
  ).freeze
end

# Good: String attribute frozen
attribute? :text, Types::String.optional
# In from_api:
text: data["text"]&.freeze
```

## Test Coverage

- [ ] **Unit tests for new value objects** - Every new Dry::Struct class needs dedicated tests
- [ ] **Edge case tests included**:
  - [ ] `nil` input handling
  - [ ] Empty string/hash/array input
  - [ ] Whitespace-only strings
  - [ ] Invalid type input
- [ ] **Error message verification** - Exception tests verify message content, not just exception type
- [ ] **`stubs.verify_stubbed_calls`** - All HTTP stub tests verify stubs were called

```ruby
# Good: Verify error message content
expect { method_call }.to raise_error(SecApi::ValidationError) do |error|
  expect(error.message).to include("missing required field")
  expect(error.message).to include("period")
end

# Good: Verify stubs in after block or inline
after { stubs.verify_stubbed_calls }
```

## Input Validation

- [ ] **Validate required parameters** - Raise ArgumentError or ValidationError for missing required input
- [ ] **URL format validation** - SEC URLs follow predictable patterns
- [ ] **CIK format handling** - Normalize to 10-digit with leading zeros
- [ ] **Accession number format** - Support both dashed and undashed formats

```ruby
# Good: Input validation with helpful error
def ticker(symbol)
  raise ArgumentError, "ticker symbol required" if symbol.nil? || symbol.empty?
  # ...
end
```

## Documentation

- [ ] **YARD docs on public methods** - `@param`, `@return`, `@raise`, `@example` tags
- [ ] **Examples match implementation** - YARD examples actually work with current code
- [ ] **@note for non-obvious behavior** - Document gotchas, limitations, or surprising behavior

```ruby
# Good: Complete YARD documentation
# Extracts XBRL data from a filing
#
# @param filing_url [String] URL to the SEC filing
# @return [XbrlData] Typed XBRL data object
# @raise [NotFoundError] when filing URL is invalid
# @raise [ValidationError] when response structure is invalid
#
# @example Extract from URL
#   data = client.xbrl.to_json("https://sec.gov/...")
#   data.statements_of_income["Revenue"]
#
# @note Element names follow US-GAAP taxonomy exactly
#
def to_json(filing_url)
```

## Code Quality

- [ ] **DRY - No duplicate code** - Extract shared logic to modules or helpers
- [ ] **Consistent patterns** - Follow established `from_api` factory method pattern
- [ ] **No dead code** - Remove commented-out code, unused variables, unreachable branches
- [ ] **StandardRB passes** - Run `bundle exec standardrb` before review

## Error Handling

- [ ] **Correct exception types**:
  - `ValidationError` - Malformed data, failed validation
  - `NotFoundError` - Resource not found (404), invalid URL
  - `AuthenticationError` - Invalid API key (401, 403)
  - `NetworkError` - Connection failures, timeouts
  - `ServerError` - API server errors (500-504)
- [ ] **Actionable error messages** - Include what failed, why, and received data context
- [ ] **No silent failures** - All errors raised or logged, never swallowed

```ruby
# Good: Actionable error message
raise ValidationError, "XBRL fact missing required 'period' field. " \
  "Received: #{data.inspect}"
```

## HTTP Testing Patterns

- [ ] **Use stub_connection/build_connection helpers** - See `spec/support/test_helpers.rb`
- [ ] **Include ErrorHandler middleware** - Required for error scenario tests
- [ ] **JSON content type in responses** - `{"Content-Type" => "application/json"}`
- [ ] **Response body as JSON string** - Use `.to_json` on response hashes

```ruby
# Good: Complete stub setup
stubs = Faraday::Adapter::Test::Stubs.new
stubs.get("/endpoint") do
  [200, {"Content-Type" => "application/json"}, {data: "value"}.to_json]
end
stub_connection(stubs)

# ... test code ...

stubs.verify_stubbed_calls
```

## Quick Self-Review

Before requesting review, ask yourself:

1. **Would this break in a multi-threaded environment?** (Sidekiq, concurrent requests)
2. **What happens if the API returns unexpected data?** (nil, wrong type, missing fields)
3. **Can someone understand this code without context?** (clear names, comments where needed)
4. **Did I test the failure paths, not just success?**
5. **Does the documentation match what the code actually does?**

---

*Checklist created from Epic 3 & 4 retrospective learnings*
*Last updated: 2026-01-07*
