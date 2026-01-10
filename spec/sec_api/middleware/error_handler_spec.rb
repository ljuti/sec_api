# frozen_string_literal: true

require "spec_helper"
require "faraday"
require "ostruct"

RSpec.describe SecApi::Middleware::ErrorHandler do
  let(:stubs) { Faraday::Adapter::Test::Stubs.new }
  let(:connection) do
    Faraday.new do |builder|
      builder.use described_class
      builder.adapter :test, stubs
    end
  end

  after { stubs.verify_stubbed_calls }

  describe "HTTP status code mapping" do
    context "when API returns 400 (Bad Request)" do
      it "raises ValidationError with actionable message" do
        stubs.get("/test") { [400, {}, "Bad request"] }

        expect {
          connection.get("/test")
        }.to raise_error(SecApi::ValidationError) do |error|
          expect(error.message).to include("400")
          expect(error.message).to include("malformed")
        end
      end

      it "inherits from PermanentError (not retryable)" do
        stubs.get("/test") { [400, {}, ""] }

        expect {
          connection.get("/test")
        }.to raise_error(SecApi::PermanentError)
      end
    end

    context "when API returns 401 (Unauthorized)" do
      it "raises AuthenticationError with actionable message" do
        stubs.get("/test") { [401, {}, "Unauthorized"] }

        expect {
          connection.get("/test")
        }.to raise_error(SecApi::AuthenticationError) do |error|
          expect(error.message).to include("401")
          expect(error.message).to include("authentication")
          expect(error.message).to include("API key")
          expect(error.message).not_to match(/[a-f0-9]{32}/) # No actual API key values
        end
      end

      it "inherits from PermanentError (not retryable)" do
        stubs.get("/test") { [401, {}, ""] }

        expect {
          connection.get("/test")
        }.to raise_error(SecApi::PermanentError)
      end
    end

    context "when API returns 403 (Forbidden)" do
      it "raises AuthenticationError with actionable message" do
        stubs.get("/test") { [403, {}, "Forbidden"] }

        expect {
          connection.get("/test")
        }.to raise_error(SecApi::AuthenticationError) do |error|
          expect(error.message).to include("403")
          expect(error.message).to include("forbidden")
          expect(error.message).to include("permission")
        end
      end

      it "inherits from PermanentError (not retryable)" do
        stubs.get("/test") { [403, {}, ""] }

        expect {
          connection.get("/test")
        }.to raise_error(SecApi::PermanentError)
      end
    end

    context "when API returns 404 (Not Found)" do
      it "raises NotFoundError with actionable message" do
        stubs.get("/test/ticker/INVALID") { [404, {}, "Not found"] }

        expect {
          connection.get("/test/ticker/INVALID")
        }.to raise_error(SecApi::NotFoundError) do |error|
          expect(error.message).to include("404")
          expect(error.message).to include("not found")
        end
      end

      it "inherits from PermanentError (not retryable)" do
        stubs.get("/test") { [404, {}, ""] }

        expect {
          connection.get("/test")
        }.to raise_error(SecApi::PermanentError)
      end
    end

    context "when API returns 422 (Unprocessable Entity)" do
      it "raises ValidationError with actionable message" do
        stubs.get("/test") { [422, {}, "Unprocessable entity"] }

        expect {
          connection.get("/test")
        }.to raise_error(SecApi::ValidationError) do |error|
          expect(error.message).to include("422")
          expect(error.message).to include("Unprocessable")
        end
      end

      it "inherits from PermanentError (not retryable)" do
        stubs.get("/test") { [422, {}, ""] }

        expect {
          connection.get("/test")
        }.to raise_error(SecApi::PermanentError)
      end
    end

    context "when API returns 429 (Rate Limit)" do
      it "raises RateLimitError with actionable message" do
        stubs.get("/test") do
          [429, {"X-RateLimit-Reset" => "1640000000"}, "Rate limit exceeded"]
        end

        expect {
          connection.get("/test")
        }.to raise_error(SecApi::RateLimitError) do |error|
          expect(error.message).to include("Rate limit exceeded")
          expect(error.message).to include("429")
          expect(error.message).to include("Rate limit resets at")
          expect(error.message).not_to include("api_key")
          expect(error.message).not_to include("Authorization")
        end
      end

      it "handles missing rate limit header gracefully" do
        stubs.get("/test") { [429, {}, "Rate limited"] }

        expect {
          connection.get("/test")
        }.to raise_error(SecApi::RateLimitError) do |error|
          expect(error.message).to include("429")
          expect(error.message).not_to include("resets at")
        end
      end

      it "inherits from TransientError for retry logic" do
        stubs.get("/test") { [429, {}, ""] }

        expect {
          connection.get("/test")
        }.to raise_error(SecApi::TransientError)
      end

      it "includes retry_after attribute when Retry-After header present" do
        stubs.get("/test") { [429, {"Retry-After" => "60"}, ""] }

        expect {
          connection.get("/test")
        }.to raise_error(SecApi::RateLimitError) do |error|
          expect(error.retry_after).to eq(60)
          expect(error.message).to include("Retry after 60 seconds")
        end
      end

      it "includes reset_at attribute when X-RateLimit-Reset header present" do
        reset_time = Time.now.to_i + 60
        stubs.get("/test") { [429, {"X-RateLimit-Reset" => reset_time.to_s}, ""] }

        expect {
          connection.get("/test")
        }.to raise_error(SecApi::RateLimitError) do |error|
          expect(error.reset_at).to eq(Time.at(reset_time))
        end
      end

      it "handles X-RateLimit-Reset timestamp in the past" do
        past_time = Time.now.to_i - 60 # 60 seconds ago
        stubs.get("/test") { [429, {"X-RateLimit-Reset" => past_time.to_s}, ""] }

        expect {
          connection.get("/test")
        }.to raise_error(SecApi::RateLimitError) do |error|
          expect(error.reset_at).to eq(Time.at(past_time))
          # Message should still include the reset time even if past
          expect(error.message).to include("Rate limit resets at")
        end
      end

      it "parses Retry-After HTTP-date format" do
        future_time = Time.now + 120
        http_date = future_time.httpdate
        stubs.get("/test") { [429, {"Retry-After" => http_date}, ""] }

        expect {
          connection.get("/test")
        }.to raise_error(SecApi::RateLimitError) do |error|
          # Should be approximately 120 seconds (allow some variance for test timing)
          expect(error.retry_after).to be_within(5).of(120)
        end
      end

      it "prefers Retry-After over X-RateLimit-Reset in message" do
        stubs.get("/test") do
          [429, {"Retry-After" => "30", "X-RateLimit-Reset" => "1640000000"}, ""]
        end

        expect {
          connection.get("/test")
        }.to raise_error(SecApi::RateLimitError) do |error|
          expect(error.retry_after).to eq(30)
          expect(error.reset_at).to eq(Time.at(1640000000))
          expect(error.message).to include("Retry after 30 seconds")
          expect(error.message).not_to include("resets at")
        end
      end

      it "handles invalid Retry-After header gracefully" do
        stubs.get("/test") { [429, {"Retry-After" => "invalid-value"}, ""] }

        expect {
          connection.get("/test")
        }.to raise_error(SecApi::RateLimitError) do |error|
          expect(error.retry_after).to be_nil
          expect(error.message).not_to include("Retry after")
        end
      end

      it "handles negative Retry-After value gracefully" do
        stubs.get("/test") { [429, {"Retry-After" => "-30"}, ""] }

        expect {
          connection.get("/test")
        }.to raise_error(SecApi::RateLimitError) do |error|
          # Negative values are parsed as integers but semantically invalid
          expect(error.retry_after).to eq(-30)
        end
      end
    end

    context "when API returns 500 (Server Error)" do
      it "raises ServerError with actionable message" do
        stubs.get("/test") { [500, {}, "Internal server error"] }

        expect {
          connection.get("/test")
        }.to raise_error(SecApi::ServerError) do |error|
          expect(error.message).to include("500")
          expect(error.message).to include("server error")
          expect(error.message).not_to include("api_key")
        end
      end

      it "inherits from TransientError" do
        stubs.get("/test") { [500, {}, ""] }

        expect {
          connection.get("/test")
        }.to raise_error(SecApi::TransientError)
      end
    end

    context "when API returns 501 (Not Implemented)" do
      it "raises ServerError" do
        stubs.get("/test") { [501, {}, "Not implemented"] }

        expect {
          connection.get("/test")
        }.to raise_error(SecApi::ServerError) do |error|
          expect(error.message).to include("501")
        end
      end
    end

    context "when API returns 502 (Bad Gateway)" do
      it "raises ServerError" do
        stubs.get("/test") { [502, {}, "Bad gateway"] }

        expect {
          connection.get("/test")
        }.to raise_error(SecApi::ServerError) do |error|
          expect(error.message).to include("502")
        end
      end
    end

    context "when API returns 503 (Service Unavailable)" do
      it "raises ServerError" do
        stubs.get("/test") { [503, {}, "Service unavailable"] }

        expect {
          connection.get("/test")
        }.to raise_error(SecApi::ServerError) do |error|
          expect(error.message).to include("503")
        end
      end
    end

    context "when API returns 504 (Gateway Timeout)" do
      it "raises ServerError" do
        stubs.get("/test") { [504, {}, "Gateway timeout"] }

        expect {
          connection.get("/test")
        }.to raise_error(SecApi::ServerError) do |error|
          expect(error.message).to include("504")
        end
      end
    end

    context "when API returns 2xx (Success)" do
      it "does not raise an error" do
        stubs.get("/test") { [200, {}, '{"success": true}'] }

        expect {
          connection.get("/test")
        }.not_to raise_error
      end
    end

    context "when API returns 3xx (Redirect)" do
      it "does not raise an error (handled by adapter)" do
        stubs.get("/test") { [301, {"Location" => "/new-location"}, ""] }

        expect {
          connection.get("/test")
        }.not_to raise_error
      end
    end
  end

  describe "Faraday exception mapping" do
    context "when Faraday::TimeoutError occurs" do
      it "raises NetworkError with actionable message" do
        # Simulate timeout by stubbing the app call in middleware
        middleware = described_class.new(->(_env) { raise Faraday::TimeoutError, "execution expired" })
        env = {method: :get, url: URI("http://example.com/test")}

        expect {
          middleware.call(env)
        }.to raise_error(SecApi::NetworkError) do |error|
          expect(error.message).to include("timeout")
          expect(error.message).to include("Original error")
        end
      end

      it "inherits from TransientError (retryable)" do
        middleware = described_class.new(->(_env) { raise Faraday::TimeoutError, "timeout" })
        env = {method: :get, url: URI("http://example.com/test")}

        expect {
          middleware.call(env)
        }.to raise_error(SecApi::TransientError)
      end
    end

    context "when Faraday::ConnectionFailed occurs" do
      it "raises NetworkError with actionable message" do
        middleware = described_class.new(->(_env) { raise Faraday::ConnectionFailed, "Failed to open TCP connection" })
        env = {method: :get, url: URI("http://example.com/test")}

        expect {
          middleware.call(env)
        }.to raise_error(SecApi::NetworkError) do |error|
          expect(error.message).to include("Connection failed")
          expect(error.message).to include("connectivity")
        end
      end

      it "inherits from TransientError (retryable)" do
        middleware = described_class.new(->(_env) { raise Faraday::ConnectionFailed, "connection failed" })
        env = {method: :get, url: URI("http://example.com/test")}

        expect {
          middleware.call(env)
        }.to raise_error(SecApi::TransientError)
      end
    end

    context "when Faraday::SSLError occurs" do
      it "raises NetworkError with actionable message" do
        middleware = described_class.new(->(_env) { raise Faraday::SSLError, "SSL certificate verification failed" })
        env = {method: :get, url: URI("https://example.com/test")}

        expect {
          middleware.call(env)
        }.to raise_error(SecApi::NetworkError) do |error|
          expect(error.message).to include("SSL/TLS error")
          expect(error.message).to include("certificate")
        end
      end

      it "inherits from TransientError (retryable)" do
        middleware = described_class.new(->(_env) { raise Faraday::SSLError, "SSL error" })
        env = {method: :get, url: URI("https://example.com/test")}

        expect {
          middleware.call(env)
        }.to raise_error(SecApi::TransientError)
      end
    end

    context "when Faraday::RetriableResponse occurs" do
      it "re-raises the exception so retry middleware can catch it" do
        middleware = described_class.new(->(_env) { raise Faraday::RetriableResponse.new(nil, {status: 503}) })
        env = {method: :get, url: URI("https://example.com/test")}

        expect {
          middleware.call(env)
        }.to raise_error(Faraday::RetriableResponse)
      end
    end
  end

  describe "error message security" do
    it "never includes API keys in error messages" do
      stubs.get("/test") do
        [401, {"Authorization" => "Bearer secret_api_key_123"}, "Unauthorized"]
      end

      expect {
        connection.get("/test")
      }.to raise_error(SecApi::AuthenticationError) do |error|
        expect(error.message).not_to include("secret_api_key")
        expect(error.message).not_to include("Bearer")
        expect(error.message).not_to include("Authorization")
      end
    end

    it "provides actionable context without sensitive data" do
      stubs.get("/test") { [429, {}, ""] }

      expect {
        connection.get("/test")
      }.to raise_error(SecApi::RateLimitError) do |error|
        expect(error.message.downcase).to include("automatic")
        expect(error.message.length).to be > 20 # Has meaningful context
      end
    end
  end

  describe "request_id propagation" do
    # Helper to create a middleware that returns a mock response
    # Uses OpenStruct to mock Faraday::Response while preserving custom keys like request_id
    def middleware_with_response(status, headers = {}, body = "")
      described_class.new(lambda { |env|
        env[:status] = status
        env[:response_headers] = headers
        env[:body] = body
        OpenStruct.new(env: env)
      })
    end

    it "includes request_id in ValidationError when env has request_id" do
      middleware = middleware_with_response(400)
      env = {method: :get, url: URI("http://example.com/test"), request_id: "req-validation-123", status: nil}

      expect {
        middleware.call(env)
      }.to raise_error(SecApi::ValidationError) do |error|
        expect(error.request_id).to eq("req-validation-123")
        expect(error.message).to include("[req-validation-123]")
      end
    end

    it "includes request_id in AuthenticationError when env has request_id" do
      middleware = middleware_with_response(401)
      env = {method: :get, url: URI("http://example.com/test"), request_id: "req-auth-456", status: nil}

      expect {
        middleware.call(env)
      }.to raise_error(SecApi::AuthenticationError) do |error|
        expect(error.request_id).to eq("req-auth-456")
        expect(error.message).to include("[req-auth-456]")
      end
    end

    it "includes request_id in NotFoundError when env has request_id" do
      middleware = middleware_with_response(404)
      env = {method: :get, url: URI("http://example.com/test"), request_id: "req-notfound-789", status: nil}

      expect {
        middleware.call(env)
      }.to raise_error(SecApi::NotFoundError) do |error|
        expect(error.request_id).to eq("req-notfound-789")
        expect(error.message).to include("[req-notfound-789]")
      end
    end

    it "includes request_id in RateLimitError when env has request_id" do
      middleware = middleware_with_response(429, {"Retry-After" => "60"})
      env = {method: :get, url: URI("http://example.com/test"), request_id: "req-ratelimit-abc", status: nil}

      expect {
        middleware.call(env)
      }.to raise_error(SecApi::RateLimitError) do |error|
        expect(error.request_id).to eq("req-ratelimit-abc")
        expect(error.message).to include("[req-ratelimit-abc]")
        expect(error.retry_after).to eq(60)
      end
    end

    it "includes request_id in ServerError when env has request_id" do
      middleware = middleware_with_response(500)
      env = {method: :get, url: URI("http://example.com/test"), request_id: "req-server-def", status: nil}

      expect {
        middleware.call(env)
      }.to raise_error(SecApi::ServerError) do |error|
        expect(error.request_id).to eq("req-server-def")
        expect(error.message).to include("[req-server-def]")
      end
    end

    it "includes request_id in NetworkError on timeout when env has request_id" do
      middleware = described_class.new(->(_env) { raise Faraday::TimeoutError, "timeout" })
      env = {method: :get, url: URI("http://example.com/test"), request_id: "req-timeout-ghi"}

      expect {
        middleware.call(env)
      }.to raise_error(SecApi::NetworkError) do |error|
        expect(error.request_id).to eq("req-timeout-ghi")
        expect(error.message).to include("[req-timeout-ghi]")
      end
    end

    it "includes request_id in NetworkError on connection failure when env has request_id" do
      middleware = described_class.new(->(_env) { raise Faraday::ConnectionFailed, "failed" })
      env = {method: :get, url: URI("http://example.com/test"), request_id: "req-conn-jkl"}

      expect {
        middleware.call(env)
      }.to raise_error(SecApi::NetworkError) do |error|
        expect(error.request_id).to eq("req-conn-jkl")
        expect(error.message).to include("[req-conn-jkl]")
      end
    end

    it "includes request_id in NetworkError on SSL error when env has request_id" do
      middleware = described_class.new(->(_env) { raise Faraday::SSLError, "SSL failed" })
      env = {method: :get, url: URI("https://example.com/test"), request_id: "req-ssl-mno"}

      expect {
        middleware.call(env)
      }.to raise_error(SecApi::NetworkError) do |error|
        expect(error.request_id).to eq("req-ssl-mno")
        expect(error.message).to include("[req-ssl-mno]")
      end
    end

    it "handles nil request_id gracefully" do
      middleware = middleware_with_response(500)
      env = {method: :get, url: URI("http://example.com/test"), status: nil}

      expect {
        middleware.call(env)
      }.to raise_error(SecApi::ServerError) do |error|
        expect(error.request_id).to be_nil
        expect(error.message).not_to include("[")
      end
    end
  end
end
