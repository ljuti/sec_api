# frozen_string_literal: true

require "spec_helper"

RSpec.describe SecApi::Middleware::RateLimiter do
  let(:tracker) { SecApi::RateLimitTracker.new }
  let(:stubs) { Faraday::Adapter::Test::Stubs.new }
  let(:connection) do
    Faraday.new do |conn|
      conn.use described_class, state_store: tracker
      conn.adapter :test, stubs
    end
  end

  after do
    stubs.verify_stubbed_calls
  end

  describe "header extraction" do
    it "extracts all rate limit headers" do
      reset_time = Time.now.to_i + 60

      stubs.get("/test") do
        [200, {
          "X-RateLimit-Limit" => "100",
          "X-RateLimit-Remaining" => "95",
          "X-RateLimit-Reset" => reset_time.to_s
        }, "{}"]
      end

      connection.get("/test")

      state = tracker.current_state
      expect(state.limit).to eq(100)
      expect(state.remaining).to eq(95)
      expect(state.reset_at).to eq(Time.at(reset_time))
    end

    it "handles lowercase headers (Faraday normalization)" do
      stubs.get("/test") do
        [200, {
          "x-ratelimit-limit" => "100",
          "x-ratelimit-remaining" => "95",
          "x-ratelimit-reset" => "1704153600"
        }, "{}"]
      end

      connection.get("/test")

      state = tracker.current_state
      expect(state.limit).to eq(100)
      expect(state.remaining).to eq(95)
    end

    it "extracts headers from error responses" do
      reset_time = Time.now.to_i + 60

      stubs.get("/test") do
        [429, {
          "X-RateLimit-Limit" => "100",
          "X-RateLimit-Remaining" => "0",
          "X-RateLimit-Reset" => reset_time.to_s
        }, "Rate limited"]
      end

      connection.get("/test")

      state = tracker.current_state
      expect(state.limit).to eq(100)
      expect(state.remaining).to eq(0)
      expect(state.exhausted?).to be true
    end

    it "updates state on each response" do
      stubs.get("/first") do
        [200, {
          "X-RateLimit-Limit" => "100",
          "X-RateLimit-Remaining" => "99"
        }, "{}"]
      end

      stubs.get("/second") do
        [200, {
          "X-RateLimit-Limit" => "100",
          "X-RateLimit-Remaining" => "98"
        }, "{}"]
      end

      connection.get("/first")
      expect(tracker.current_state.remaining).to eq(99)

      connection.get("/second")
      expect(tracker.current_state.remaining).to eq(98)
    end
  end

  describe "missing headers" do
    it "does not update state when no rate limit headers present" do
      stubs.get("/test") do
        [200, {"Content-Type" => "application/json"}, "{}"]
      end

      connection.get("/test")

      expect(tracker.current_state).to be_nil
    end

    it "updates state with partial headers" do
      stubs.get("/test") do
        [200, {
          "X-RateLimit-Remaining" => "95"
        }, "{}"]
      end

      connection.get("/test")

      state = tracker.current_state
      expect(state.limit).to be_nil
      expect(state.remaining).to eq(95)
      expect(state.reset_at).to be_nil
    end

    it "handles empty header values" do
      stubs.get("/test") do
        [200, {
          "X-RateLimit-Limit" => "",
          "X-RateLimit-Remaining" => "95"
        }, "{}"]
      end

      connection.get("/test")

      state = tracker.current_state
      expect(state.limit).to be_nil
      expect(state.remaining).to eq(95)
    end
  end

  describe "invalid header values" do
    it "handles non-numeric limit gracefully" do
      stubs.get("/test") do
        [200, {
          "X-RateLimit-Limit" => "unlimited",
          "X-RateLimit-Remaining" => "95"
        }, "{}"]
      end

      connection.get("/test")

      state = tracker.current_state
      expect(state.limit).to be_nil
      expect(state.remaining).to eq(95)
    end

    it "handles non-numeric reset timestamp gracefully" do
      stubs.get("/test") do
        [200, {
          "X-RateLimit-Limit" => "100",
          "X-RateLimit-Reset" => "tomorrow"
        }, "{}"]
      end

      connection.get("/test")

      state = tracker.current_state
      expect(state.limit).to eq(100)
      expect(state.reset_at).to be_nil
    end
  end

  describe "without state store" do
    let(:connection_without_store) do
      Faraday.new do |conn|
        conn.use described_class
        conn.adapter :test, stubs
      end
    end

    it "handles requests gracefully without state store" do
      stubs.get("/test") do
        [200, {
          "X-RateLimit-Limit" => "100",
          "X-RateLimit-Remaining" => "95"
        }, "{}"]
      end

      expect { connection_without_store.get("/test") }.not_to raise_error
    end
  end

  describe "response passthrough" do
    it "returns the original response unmodified" do
      stubs.get("/test") do
        [200, {
          "X-RateLimit-Limit" => "100",
          "Content-Type" => "application/json"
        }, '{"data": "test"}']
      end

      response = connection.get("/test")

      expect(response.status).to eq(200)
      expect(response.body).to eq('{"data": "test"}')
    end
  end
end
