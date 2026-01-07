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

  describe "proactive throttling" do
    let(:threshold) { 0.1 } # 10%
    let(:connection_with_throttle) do
      Faraday.new do |conn|
        conn.use described_class, state_store: tracker, threshold: threshold
        conn.adapter :test, stubs
      end
    end

    describe "#should_throttle?" do
      it "throttles when percentage_remaining is below threshold" do
        # Set up state: 9% remaining (below 10% threshold)
        tracker.update(limit: 100, remaining: 9, reset_at: Time.now + 60)

        stubs.get("/test") { [200, {}, "{}"] }

        expect_any_instance_of(described_class).to receive(:sleep).with(a_value > 0)
        connection_with_throttle.get("/test")
      end

      it "does NOT throttle when percentage_remaining equals threshold" do
        # Set up state: exactly 10% remaining (at threshold boundary)
        tracker.update(limit: 100, remaining: 10, reset_at: Time.now + 60)

        stubs.get("/test") { [200, {}, "{}"] }

        expect_any_instance_of(described_class).not_to receive(:sleep)
        connection_with_throttle.get("/test")
      end

      it "does NOT throttle when percentage_remaining is above threshold" do
        # Set up state: 50% remaining (well above threshold)
        tracker.update(limit: 100, remaining: 50, reset_at: Time.now + 60)

        stubs.get("/test") { [200, {}, "{}"] }

        expect_any_instance_of(described_class).not_to receive(:sleep)
        connection_with_throttle.get("/test")
      end

      it "does NOT throttle when no state exists" do
        # No prior state
        expect(tracker.current_state).to be_nil

        stubs.get("/test") { [200, {}, "{}"] }

        expect_any_instance_of(described_class).not_to receive(:sleep)
        connection_with_throttle.get("/test")
      end

      it "does NOT throttle when percentage_remaining is nil" do
        # State exists but limit is nil (percentage can't be calculated)
        tracker.update(limit: nil, remaining: 5, reset_at: Time.now + 60)

        stubs.get("/test") { [200, {}, "{}"] }

        expect_any_instance_of(described_class).not_to receive(:sleep)
        connection_with_throttle.get("/test")
      end
    end

    describe "#calculate_delay" do
      it "calculates delay until reset time" do
        reset_time = Time.now + 30
        tracker.update(limit: 100, remaining: 5, reset_at: reset_time)

        stubs.get("/test") { [200, {}, "{}"] }

        # Expect sleep with approximately 30 seconds (allowing for execution time)
        expect_any_instance_of(described_class).to receive(:sleep) do |_instance, delay|
          expect(delay).to be_within(1).of(30)
        end
        connection_with_throttle.get("/test")
      end

      it "does NOT sleep when reset_at is nil" do
        tracker.update(limit: 100, remaining: 5, reset_at: nil)  # no reset_at

        stubs.get("/test") { [200, {}, "{}"] }

        expect_any_instance_of(described_class).not_to receive(:sleep)
        connection_with_throttle.get("/test")
      end

      it "does NOT sleep when reset time has passed" do
        # Reset time in the past
        tracker.update(limit: 100, remaining: 5, reset_at: Time.now - 10)

        stubs.get("/test") { [200, {}, "{}"] }

        expect_any_instance_of(described_class).not_to receive(:sleep)
        connection_with_throttle.get("/test")
      end
    end

    describe "custom threshold" do
      let(:threshold) { 0.2 } # 20%

      it "throttles at custom threshold boundary" do
        # 19% remaining (below 20% threshold)
        tracker.update(limit: 100, remaining: 19, reset_at: Time.now + 60)

        stubs.get("/test") { [200, {}, "{}"] }

        expect_any_instance_of(described_class).to receive(:sleep).with(a_value > 0)
        connection_with_throttle.get("/test")
      end

      it "does NOT throttle above custom threshold" do
        # 20% remaining (at threshold boundary)
        tracker.update(limit: 100, remaining: 20, reset_at: Time.now + 60)

        stubs.get("/test") { [200, {}, "{}"] }

        expect_any_instance_of(described_class).not_to receive(:sleep)
        connection_with_throttle.get("/test")
      end
    end

    describe "boundary threshold values" do
      describe "threshold 0.0 (never throttle)" do
        let(:connection_zero_threshold) do
          Faraday.new do |conn|
            conn.use described_class, state_store: tracker, threshold: 0.0
            conn.adapter :test, stubs
          end
        end

        it "never throttles even at 0% remaining" do
          # 0% remaining - but threshold is 0.0, so 0 is NOT < 0
          tracker.update(limit: 100, remaining: 0, reset_at: Time.now + 60)

          stubs.get("/test") { [200, {}, "{}"] }

          expect_any_instance_of(described_class).not_to receive(:sleep)
          connection_zero_threshold.get("/test")
        end

        it "never throttles at 1% remaining" do
          tracker.update(limit: 100, remaining: 1, reset_at: Time.now + 60)

          stubs.get("/test") { [200, {}, "{}"] }

          expect_any_instance_of(described_class).not_to receive(:sleep)
          connection_zero_threshold.get("/test")
        end
      end

      describe "threshold 1.0 (always throttle)" do
        let(:connection_full_threshold) do
          Faraday.new do |conn|
            conn.use described_class, state_store: tracker, threshold: 1.0
            conn.adapter :test, stubs
          end
        end

        it "throttles at 99% remaining (below 100% threshold)" do
          tracker.update(limit: 100, remaining: 99, reset_at: Time.now + 60)

          stubs.get("/test") { [200, {}, "{}"] }

          expect_any_instance_of(described_class).to receive(:sleep).with(a_value > 0)
          connection_full_threshold.get("/test")
        end

        it "throttles at 50% remaining" do
          tracker.update(limit: 100, remaining: 50, reset_at: Time.now + 60)

          stubs.get("/test") { [200, {}, "{}"] }

          expect_any_instance_of(described_class).to receive(:sleep).with(a_value > 0)
          connection_full_threshold.get("/test")
        end

        it "does NOT throttle at exactly 100% remaining (boundary)" do
          # 100% remaining is NOT < 100%, so no throttle
          tracker.update(limit: 100, remaining: 100, reset_at: Time.now + 60)

          stubs.get("/test") { [200, {}, "{}"] }

          expect_any_instance_of(described_class).not_to receive(:sleep)
          connection_full_threshold.get("/test")
        end
      end
    end

    describe "without threshold configured" do
      let(:connection_no_threshold) do
        Faraday.new do |conn|
          conn.use described_class, state_store: tracker
          conn.adapter :test, stubs
        end
      end

      it "uses default threshold of 0.1 (10%)" do
        # 9% remaining (below default 10% threshold)
        tracker.update(limit: 100, remaining: 9, reset_at: Time.now + 60)

        stubs.get("/test") { [200, {}, "{}"] }

        expect_any_instance_of(described_class).to receive(:sleep).with(a_value > 0)
        connection_no_threshold.get("/test")
      end
    end

    describe "on_throttle callback" do
      let(:callback_received) { [] }
      let(:on_throttle) { ->(info) { callback_received << info } }
      let(:connection_with_callback) do
        Faraday.new do |conn|
          conn.use described_class, state_store: tracker, threshold: 0.1, on_throttle: on_throttle
          conn.adapter :test, stubs
        end
      end

      it "invokes callback with throttle info when throttling" do
        reset_time = Time.now + 30
        tracker.update(limit: 100, remaining: 5, reset_at: reset_time)

        stubs.get("/test") { [200, {}, "{}"] }

        allow_any_instance_of(described_class).to receive(:sleep)
        connection_with_callback.get("/test")

        expect(callback_received.size).to eq(1)
        info = callback_received.first
        expect(info[:remaining]).to eq(5)
        expect(info[:limit]).to eq(100)
        expect(info[:delay]).to be_within(1).of(30)
        expect(info[:reset_at]).to eq(reset_time)
      end

      it "does NOT invoke callback when not throttling" do
        # Above threshold - no throttling
        tracker.update(limit: 100, remaining: 50, reset_at: Time.now + 60)

        stubs.get("/test") { [200, {}, "{}"] }

        connection_with_callback.get("/test")

        expect(callback_received).to be_empty
      end

      it "handles nil callback gracefully" do
        connection_no_callback = Faraday.new do |conn|
          conn.use described_class, state_store: tracker, threshold: 0.1, on_throttle: nil
          conn.adapter :test, stubs
        end

        tracker.update(limit: 100, remaining: 5, reset_at: Time.now + 30)
        stubs.get("/test") { [200, {}, "{}"] }

        allow_any_instance_of(described_class).to receive(:sleep)
        expect { connection_no_callback.get("/test") }.not_to raise_error
      end
    end

    describe "integration: request flow with throttling" do
      let(:callback_log) { [] }
      let(:on_throttle) { ->(info) { callback_log << info } }
      let(:connection_integration) do
        Faraday.new do |conn|
          conn.use described_class, state_store: tracker, threshold: 0.1, on_throttle: on_throttle
          conn.adapter :test, stubs
        end
      end

      it "completes full throttle cycle: no throttle on first request, throttle when below threshold" do
        # Request 1: Initial request - no state yet, so no throttle
        stubs.get("/first") do
          [200, {
            "X-RateLimit-Limit" => "100",
            "X-RateLimit-Remaining" => "8",  # 8% remaining (below 10% threshold)
            "X-RateLimit-Reset" => (Time.now + 60).to_i.to_s
          }, "{}"]
        end

        connection_integration.get("/first")
        expect(tracker.current_state.remaining).to eq(8)
        expect(callback_log).to be_empty  # No throttle on first request (state was nil before)

        # Request 2: Should throttle because state shows < 10% remaining
        stubs.get("/second") do
          [200, {
            "X-RateLimit-Limit" => "100",
            "X-RateLimit-Remaining" => "7",
            "X-RateLimit-Reset" => (Time.now + 60).to_i.to_s
          }, "{}"]
        end

        expect_any_instance_of(described_class).to receive(:sleep).with(a_value > 0)
        connection_integration.get("/second")
        expect(callback_log.size).to eq(1)
        expect(callback_log.first[:remaining]).to eq(8)  # State before request
      end

      it "no throttle when above threshold" do
        # Set up state above threshold
        stubs.get("/first") do
          [200, {
            "X-RateLimit-Limit" => "100",
            "X-RateLimit-Remaining" => "50",  # 50% remaining (above 10% threshold)
            "X-RateLimit-Reset" => (Time.now + 60).to_i.to_s
          }, "{}"]
        end

        connection_integration.get("/first")

        # Request 2: Should NOT throttle because 50% > 10%
        stubs.get("/second") do
          [200, {
            "X-RateLimit-Limit" => "100",
            "X-RateLimit-Remaining" => "49",
            "X-RateLimit-Reset" => (Time.now + 60).to_i.to_s
          }, "{}"]
        end

        expect_any_instance_of(described_class).not_to receive(:sleep)
        connection_integration.get("/second")
        expect(callback_log).to be_empty
      end

      it "no throttle when reset time has passed" do
        # Set up state with reset time in the past
        past_time = Time.now - 10
        tracker.update(limit: 100, remaining: 5, reset_at: past_time)

        stubs.get("/test") do
          [200, {
            "X-RateLimit-Limit" => "100",
            "X-RateLimit-Remaining" => "95",
            "X-RateLimit-Reset" => (Time.now + 60).to_i.to_s
          }, "{}"]
        end

        # Should NOT throttle because reset_at is in the past
        expect_any_instance_of(described_class).not_to receive(:sleep)
        connection_integration.get("/test")
        expect(callback_log).to be_empty
      end
    end
  end
end
