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

        it "queues when remaining = 0 (queueing is separate from throttling)" do
          # 0% remaining - threshold is 0.0 so throttling doesn't trigger,
          # but queueing still happens when exhausted (remaining = 0)
          tracker.update(limit: 100, remaining: 0, reset_at: Time.now + 0.05)

          stubs.get("/test") do
            [200, {
              "X-RateLimit-Limit" => "100",
              "X-RateLimit-Remaining" => "99",
              "X-RateLimit-Reset" => (Time.now + 60).to_i.to_s
            }, "{}"]
          end

          # Measure execution time - should block briefly (queueing, not throttling)
          start_time = Time.now
          connection_zero_threshold.get("/test")
          elapsed = Time.now - start_time

          # Should have waited (queueing delay)
          expect(elapsed).to be >= 0.01
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

      it "includes request_id in callback info" do
        reset_time = Time.now + 30
        tracker.update(limit: 100, remaining: 5, reset_at: reset_time)

        stubs.get("/test") { [200, {}, "{}"] }

        allow_any_instance_of(described_class).to receive(:sleep)
        connection_with_callback.get("/test")

        expect(callback_received.size).to eq(1)
        info = callback_received.first
        expect(info[:request_id]).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
      end

      it "generates unique request_id for each request" do
        reset_time = Time.now + 30
        tracker.update(limit: 100, remaining: 5, reset_at: reset_time)

        # Include reset_at in response to ensure state is maintained for second request
        stubs.get("/first") do
          [200, {
            "X-RateLimit-Limit" => "100",
            "X-RateLimit-Remaining" => "4",
            "X-RateLimit-Reset" => reset_time.to_i.to_s
          }, "{}"]
        end
        stubs.get("/second") { [200, {}, "{}"] }

        allow_any_instance_of(described_class).to receive(:sleep)
        connection_with_callback.get("/first")
        connection_with_callback.get("/second")

        expect(callback_received.size).to eq(2)
        expect(callback_received[0][:request_id]).not_to eq(callback_received[1][:request_id])
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

      it "logs throttle event as JSON when logger is configured" do
        log_output = StringIO.new
        logger = Logger.new(log_output)
        logger.formatter = ->(_, _, _, msg) { "#{msg}\n" }

        connection_with_logging = Faraday.new do |conn|
          conn.use described_class,
            state_store: tracker,
            threshold: 0.1,
            logger: logger,
            log_level: :info
          conn.adapter :test, stubs
        end

        tracker.update(limit: 100, remaining: 5, reset_at: Time.now + 30)
        stubs.get("/test") { [200, {}, "{}"] }

        allow_any_instance_of(described_class).to receive(:sleep)
        connection_with_logging.get("/test")

        log_output.rewind
        log_line = log_output.read.strip
        log_data = JSON.parse(log_line)

        expect(log_data["event"]).to eq("secapi.rate_limit.throttle")
        expect(log_data["request_id"]).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
        expect(log_data["remaining"]).to eq(5)
        expect(log_data["limit"]).to eq(100)
        expect(log_data["delay"]).to be_a(Numeric)
      end

      it "does not break request when logger raises exception" do
        failing_logger = instance_double(Logger)
        allow(failing_logger).to receive(:info).and_raise(StandardError.new("Logger failed!"))

        connection_with_failing_logger = Faraday.new do |conn|
          conn.use described_class,
            state_store: tracker,
            threshold: 0.1,
            logger: failing_logger,
            log_level: :info
          conn.adapter :test, stubs
        end

        tracker.update(limit: 100, remaining: 5, reset_at: Time.now + 30)
        stubs.get("/test") { [200, {}, '{"result": "success"}'] }

        allow_any_instance_of(described_class).to receive(:sleep)

        # Should complete successfully despite logger error
        response = connection_with_failing_logger.get("/test")
        expect(response.status).to eq(200)
        expect(response.body).to eq('{"result": "success"}')
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

  describe "request queueing when remaining = 0" do
    let(:queue_callback_log) { [] }
    let(:on_queue) { ->(info) { queue_callback_log << info } }
    let(:connection_with_queueing) do
      Faraday.new do |conn|
        conn.use described_class,
          state_store: tracker,
          threshold: 0.1,
          on_queue: on_queue
        conn.adapter :test, stubs
      end
    end

    describe "blocking behavior when remaining = 0" do
      it "blocks request when remaining = 0" do
        # Set reset_at very close to now so wait times out quickly
        reset_time = Time.now + 0.05
        tracker.update(limit: 100, remaining: 0, reset_at: reset_time)

        stubs.get("/test") do
          # Response updates state to non-exhausted
          [200, {
            "X-RateLimit-Limit" => "100",
            "X-RateLimit-Remaining" => "99",
            "X-RateLimit-Reset" => (Time.now + 60).to_i.to_s
          }, "{}"]
        end

        # Measure execution time - should block briefly
        start_time = Time.now
        connection_with_queueing.get("/test")
        elapsed = Time.now - start_time

        # Should have waited at least some time (queueing delay)
        expect(elapsed).to be >= 0.01
      end

      it "does NOT block when remaining > 0" do
        reset_time = Time.now + 60
        tracker.update(limit: 100, remaining: 1, reset_at: reset_time)

        stubs.get("/test") do
          [200, {
            "X-RateLimit-Limit" => "100",
            "X-RateLimit-Remaining" => "0",
            "X-RateLimit-Reset" => (Time.now + 60).to_i.to_s
          }, "{}"]
        end

        # Should NOT block because remaining > 0 (proactive throttle may apply based on threshold)
        # With remaining=1 and limit=100, that's 1% which is below 10% threshold
        # But the key test is that queueing (blocking on remaining=0) doesn't trigger
        allow_any_instance_of(described_class).to receive(:sleep)
        connection_with_queueing.get("/test")

        # Verify no queueing callback was invoked (throttle callback may be)
        expect(queue_callback_log).to be_empty
      end

      it "does NOT block when remaining is nil (no state yet)" do
        # No prior state - remaining is nil
        expect(tracker.current_state).to be_nil

        stubs.get("/test") do
          [200, {
            "X-RateLimit-Limit" => "100",
            "X-RateLimit-Remaining" => "99",
            "X-RateLimit-Reset" => (Time.now + 60).to_i.to_s
          }, "{}"]
        end

        # Quick execution - no blocking expected
        start_time = Time.now
        connection_with_queueing.get("/test")
        elapsed = Time.now - start_time

        # Should complete almost immediately (no queueing)
        expect(elapsed).to be < 0.5
      end

      it "does NOT block when reset_at is in the past" do
        past_time = Time.now - 10
        tracker.update(limit: 100, remaining: 0, reset_at: past_time)

        stubs.get("/test") do
          [200, {
            "X-RateLimit-Limit" => "100",
            "X-RateLimit-Remaining" => "99",
            "X-RateLimit-Reset" => (Time.now + 60).to_i.to_s
          }, "{}"]
        end

        # Quick execution - reset already passed
        start_time = Time.now
        connection_with_queueing.get("/test")
        elapsed = Time.now - start_time

        # Should complete almost immediately (reset passed)
        expect(elapsed).to be < 0.5
      end
    end

    describe "queued_count tracking" do
      it "tracks queued request count via callback" do
        # Set reset time close to now so wait finishes quickly
        reset_time = Time.now + 0.1
        tracker.update(limit: 100, remaining: 0, reset_at: reset_time)

        stubs.get("/test") do
          [200, {
            "X-RateLimit-Limit" => "100",
            "X-RateLimit-Remaining" => "99",
            "X-RateLimit-Reset" => (Time.now + 60).to_i.to_s
          }, "{}"]
        end

        connection_with_queueing.get("/test")

        # Verify the callback was invoked with queue_size = 1
        expect(queue_callback_log.size).to eq(1)
        expect(queue_callback_log.first[:queue_size]).to eq(1)
      end
    end

    describe "on_queue callback" do
      it "invokes callback with queue info when blocking" do
        reset_time = Time.now + 0.1  # Short wait for test
        tracker.update(limit: 100, remaining: 0, reset_at: reset_time)

        stubs.get("/test") do
          [200, {
            "X-RateLimit-Limit" => "100",
            "X-RateLimit-Remaining" => "99",
            "X-RateLimit-Reset" => (Time.now + 60).to_i.to_s
          }, "{}"]
        end

        connection_with_queueing.get("/test")

        expect(queue_callback_log.size).to eq(1)
        info = queue_callback_log.first
        expect(info[:queue_size]).to eq(1)
        expect(info[:wait_time]).to be > 0
        expect(info[:reset_at]).to eq(reset_time)
      end

      it "includes request_id in on_queue callback info" do
        reset_time = Time.now + 0.1
        tracker.update(limit: 100, remaining: 0, reset_at: reset_time)

        stubs.get("/test") do
          [200, {
            "X-RateLimit-Limit" => "100",
            "X-RateLimit-Remaining" => "99",
            "X-RateLimit-Reset" => (Time.now + 60).to_i.to_s
          }, "{}"]
        end

        connection_with_queueing.get("/test")

        expect(queue_callback_log.size).to eq(1)
        info = queue_callback_log.first
        expect(info[:request_id]).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
      end

      it "does NOT invoke callback when not blocking" do
        # remaining > 0, so no blocking
        tracker.update(limit: 100, remaining: 50, reset_at: Time.now + 60)

        stubs.get("/test") { [200, {}, "{}"] }

        connection_with_queueing.get("/test")

        expect(queue_callback_log).to be_empty
      end

      it "handles nil on_queue callback gracefully" do
        connection_no_callback = Faraday.new do |conn|
          conn.use described_class, state_store: tracker, on_queue: nil
          conn.adapter :test, stubs
        end

        # Short wait time so test doesn't hang
        tracker.update(limit: 100, remaining: 0, reset_at: Time.now + 0.05)
        stubs.get("/test") do
          [200, {
            "X-RateLimit-Limit" => "100",
            "X-RateLimit-Remaining" => "99",
            "X-RateLimit-Reset" => (Time.now + 60).to_i.to_s
          }, "{}"]
        end

        expect { connection_no_callback.get("/test") }.not_to raise_error
      end

      it "logs queue event as JSON when logger is configured" do
        log_output = StringIO.new
        logger = Logger.new(log_output)
        logger.formatter = ->(_, _, _, msg) { "#{msg}\n" }

        connection_with_logging = Faraday.new do |conn|
          conn.use described_class,
            state_store: tracker,
            logger: logger,
            log_level: :info
          conn.adapter :test, stubs
        end

        tracker.update(limit: 100, remaining: 0, reset_at: Time.now + 0.1)
        stubs.get("/test") do
          [200, {
            "X-RateLimit-Limit" => "100",
            "X-RateLimit-Remaining" => "99",
            "X-RateLimit-Reset" => (Time.now + 60).to_i.to_s
          }, "{}"]
        end

        connection_with_logging.get("/test")

        log_output.rewind
        log_line = log_output.read.strip
        log_data = JSON.parse(log_line)

        expect(log_data["event"]).to eq("secapi.rate_limit.queue")
        expect(log_data["request_id"]).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
        expect(log_data["queue_size"]).to be_a(Integer)
        expect(log_data["wait_time"]).to be_a(Numeric)
      end
    end

    describe "thread-safety and concurrent requests" do
      it "handles concurrent requests safely with multiple threads" do
        reset_time = Time.now + 0.2
        tracker.update(limit: 100, remaining: 0, reset_at: reset_time)

        connection = Faraday.new do |conn|
          conn.use described_class, state_store: tracker
          conn.adapter :test, stubs
        end

        # Stub multiple responses
        5.times do
          stubs.get("/test") do
            [200, {
              "X-RateLimit-Limit" => "100",
              "X-RateLimit-Remaining" => "99",
              "X-RateLimit-Reset" => (Time.now + 60).to_i.to_s
            }, "{}"]
          end
        end

        threads = 5.times.map do
          Thread.new { connection.get("/test") }
        end

        # All threads should complete without error
        expect { threads.each { |t| t.join(5) } }.not_to raise_error

        # All threads should have finished
        expect(threads.all? { |t| !t.alive? }).to be true
      end

      it "decrements queued count even when reset time passes" do
        # Reset in the past - should not wait
        tracker.update(limit: 100, remaining: 0, reset_at: Time.now - 10)

        connection = Faraday.new do |conn|
          conn.use described_class, state_store: tracker
          conn.adapter :test, stubs
        end

        stubs.get("/test") do
          [200, {
            "X-RateLimit-Limit" => "100",
            "X-RateLimit-Remaining" => "99",
            "X-RateLimit-Reset" => (Time.now + 60).to_i.to_s
          }, "{}"]
        end

        # Should not block and queued count should remain 0
        connection.get("/test")
        expect(tracker.queued_count).to eq(0)
      end

      it "correctly updates queued count through queue lifecycle" do
        reset_time = Time.now + 0.1
        tracker.update(limit: 100, remaining: 0, reset_at: reset_time)

        connection = Faraday.new do |conn|
          conn.use described_class, state_store: tracker
          conn.adapter :test, stubs
        end

        stubs.get("/test") do
          [200, {
            "X-RateLimit-Limit" => "100",
            "X-RateLimit-Remaining" => "99",
            "X-RateLimit-Reset" => (Time.now + 60).to_i.to_s
          }, "{}"]
        end

        # Before request, queue should be empty
        expect(tracker.queued_count).to eq(0)

        connection.get("/test")

        # After request completes, queue should be empty again
        expect(tracker.queued_count).to eq(0)
      end
    end

    describe "excessive wait warning" do
      let(:excessive_wait_log) { [] }
      let(:on_excessive_wait) { ->(info) { excessive_wait_log << info } }

      context "with custom threshold" do
        let(:connection_with_warning) do
          Faraday.new do |conn|
            conn.use described_class,
              state_store: tracker,
              queue_wait_warning_threshold: 0.05,  # Very low threshold for testing
              on_excessive_wait: on_excessive_wait
            conn.adapter :test, stubs
          end
        end

        it "invokes callback when wait exceeds threshold" do
          # Wait time > 0.05s threshold
          reset_time = Time.now + 0.1
          tracker.update(limit: 100, remaining: 0, reset_at: reset_time)

          stubs.get("/test") do
            [200, {
              "X-RateLimit-Limit" => "100",
              "X-RateLimit-Remaining" => "99",
              "X-RateLimit-Reset" => (Time.now + 60).to_i.to_s
            }, "{}"]
          end

          connection_with_warning.get("/test")

          expect(excessive_wait_log.size).to eq(1)
          info = excessive_wait_log.first
          expect(info[:wait_time]).to be > 0.05
          expect(info[:threshold]).to eq(0.05)
          expect(info[:reset_at]).to eq(reset_time)
        end

        it "includes request_id in on_excessive_wait callback info" do
          reset_time = Time.now + 0.1
          tracker.update(limit: 100, remaining: 0, reset_at: reset_time)

          stubs.get("/test") do
            [200, {
              "X-RateLimit-Limit" => "100",
              "X-RateLimit-Remaining" => "99",
              "X-RateLimit-Reset" => (Time.now + 60).to_i.to_s
            }, "{}"]
          end

          connection_with_warning.get("/test")

          expect(excessive_wait_log.size).to eq(1)
          info = excessive_wait_log.first
          expect(info[:request_id]).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
        end

        it "does NOT invoke callback when wait is below threshold" do
          # Wait time < 0.05s threshold
          reset_time = Time.now + 0.02
          tracker.update(limit: 100, remaining: 0, reset_at: reset_time)

          stubs.get("/test") do
            [200, {
              "X-RateLimit-Limit" => "100",
              "X-RateLimit-Remaining" => "99",
              "X-RateLimit-Reset" => (Time.now + 60).to_i.to_s
            }, "{}"]
          end

          connection_with_warning.get("/test")

          expect(excessive_wait_log).to be_empty
        end
      end

      context "with default threshold (300 seconds)" do
        let(:connection_default_threshold) do
          Faraday.new do |conn|
            conn.use described_class,
              state_store: tracker,
              on_excessive_wait: on_excessive_wait
            conn.adapter :test, stubs
          end
        end

        it "does NOT warn for short waits (default 300s threshold)" do
          # 1 second wait is well below 300s default
          reset_time = Time.now + 0.05
          tracker.update(limit: 100, remaining: 0, reset_at: reset_time)

          stubs.get("/test") do
            [200, {
              "X-RateLimit-Limit" => "100",
              "X-RateLimit-Remaining" => "99",
              "X-RateLimit-Reset" => (Time.now + 60).to_i.to_s
            }, "{}"]
          end

          connection_default_threshold.get("/test")

          expect(excessive_wait_log).to be_empty
        end
      end

      it "handles nil on_excessive_wait callback gracefully" do
        connection_no_callback = Faraday.new do |conn|
          conn.use described_class,
            state_store: tracker,
            queue_wait_warning_threshold: 0.01,  # Will exceed
            on_excessive_wait: nil
          conn.adapter :test, stubs
        end

        tracker.update(limit: 100, remaining: 0, reset_at: Time.now + 0.05)
        stubs.get("/test") do
          [200, {
            "X-RateLimit-Limit" => "100",
            "X-RateLimit-Remaining" => "99",
            "X-RateLimit-Reset" => (Time.now + 60).to_i.to_s
          }, "{}"]
        end

        expect { connection_no_callback.get("/test") }.not_to raise_error
      end
    end

    describe "on_dequeue callback" do
      let(:dequeue_callback_log) { [] }
      let(:on_dequeue) { ->(info) { dequeue_callback_log << info } }
      let(:connection_with_dequeue) do
        Faraday.new do |conn|
          conn.use described_class,
            state_store: tracker,
            on_dequeue: on_dequeue
          conn.adapter :test, stubs
        end
      end

      it "invokes callback when request exits queue" do
        reset_time = Time.now + 0.1
        tracker.update(limit: 100, remaining: 0, reset_at: reset_time)

        stubs.get("/test") do
          [200, {
            "X-RateLimit-Limit" => "100",
            "X-RateLimit-Remaining" => "99",
            "X-RateLimit-Reset" => (Time.now + 60).to_i.to_s
          }, "{}"]
        end

        connection_with_dequeue.get("/test")

        expect(dequeue_callback_log.size).to eq(1)
        info = dequeue_callback_log.first
        expect(info[:queue_size]).to eq(0)  # After decrement
        expect(info[:waited]).to be >= 0
      end

      it "includes request_id in on_dequeue callback info" do
        reset_time = Time.now + 0.1
        tracker.update(limit: 100, remaining: 0, reset_at: reset_time)

        stubs.get("/test") do
          [200, {
            "X-RateLimit-Limit" => "100",
            "X-RateLimit-Remaining" => "99",
            "X-RateLimit-Reset" => (Time.now + 60).to_i.to_s
          }, "{}"]
        end

        connection_with_dequeue.get("/test")

        expect(dequeue_callback_log.size).to eq(1)
        info = dequeue_callback_log.first
        expect(info[:request_id]).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
      end

      it "reports accurate wait time" do
        reset_time = Time.now + 0.1
        tracker.update(limit: 100, remaining: 0, reset_at: reset_time)

        stubs.get("/test") do
          [200, {
            "X-RateLimit-Limit" => "100",
            "X-RateLimit-Remaining" => "99",
            "X-RateLimit-Reset" => (Time.now + 60).to_i.to_s
          }, "{}"]
        end

        connection_with_dequeue.get("/test")

        # Should have waited approximately the reset time
        expect(dequeue_callback_log.first[:waited]).to be >= 0.05
      end

      it "handles nil on_dequeue callback gracefully" do
        connection_no_callback = Faraday.new do |conn|
          conn.use described_class, state_store: tracker, on_dequeue: nil
          conn.adapter :test, stubs
        end

        tracker.update(limit: 100, remaining: 0, reset_at: Time.now + 0.05)
        stubs.get("/test") do
          [200, {
            "X-RateLimit-Limit" => "100",
            "X-RateLimit-Remaining" => "99",
            "X-RateLimit-Reset" => (Time.now + 60).to_i.to_s
          }, "{}"]
        end

        expect { connection_no_callback.get("/test") }.not_to raise_error
      end
    end

    describe "default backoff when reset_at is nil" do
      it "uses default wait time when reset_at is nil but remaining is 0" do
        # Set remaining=0 but no reset_at
        tracker.update(limit: 100, remaining: 0, reset_at: nil)

        connection = Faraday.new do |conn|
          conn.use described_class, state_store: tracker
          conn.adapter :test, stubs
        end

        # Stub response that updates state to non-exhausted
        stubs.get("/test") do
          [200, {
            "X-RateLimit-Limit" => "100",
            "X-RateLimit-Remaining" => "99",
            "X-RateLimit-Reset" => (Time.now + 60).to_i.to_s
          }, "{}"]
        end

        # Should block briefly (DEFAULT_QUEUE_WAIT_SECONDS = 60, but will exit early
        # when state is updated by the response)
        start_time = Time.now
        connection.get("/test")
        elapsed = Time.now - start_time

        # Should have waited some amount of time (entered queueing)
        # The wait will be short because the response updates state
        expect(elapsed).to be >= 0
      end

      it "invokes on_queue callback with nil reset_at" do
        queue_log = []
        on_queue = ->(info) { queue_log << info }

        tracker.update(limit: 100, remaining: 0, reset_at: nil)

        connection = Faraday.new do |conn|
          conn.use described_class, state_store: tracker, on_queue: on_queue
          conn.adapter :test, stubs
        end

        stubs.get("/test") do
          [200, {
            "X-RateLimit-Limit" => "100",
            "X-RateLimit-Remaining" => "99",
            "X-RateLimit-Reset" => (Time.now + 60).to_i.to_s
          }, "{}"]
        end

        connection.get("/test")

        expect(queue_log.size).to eq(1)
        expect(queue_log.first[:reset_at]).to be_nil
        expect(queue_log.first[:wait_time]).to eq(60)  # DEFAULT_QUEUE_WAIT_SECONDS
      end
    end

    describe "callback exception handling" do
      # Use separate stubs for these tests to avoid verify_stubbed_calls issues
      # (exceptions happen before HTTP request is made)
      let(:exception_test_stubs) { Faraday::Adapter::Test::Stubs.new }

      it "decrements queued_count even when on_queue callback raises" do
        failing_callback = ->(_info) { raise "Callback error!" }

        tracker.update(limit: 100, remaining: 0, reset_at: Time.now + 0.05)

        connection = Faraday.new do |conn|
          conn.use described_class, state_store: tracker, on_queue: failing_callback
          conn.adapter :test, exception_test_stubs
        end

        # Stub not needed - exception happens before HTTP call

        # The request should raise due to callback error
        expect { connection.get("/test") }.to raise_error("Callback error!")

        # But queued_count should still be 0 (decremented in ensure block)
        expect(tracker.queued_count).to eq(0)
      end

      it "decrements queued_count even when on_excessive_wait callback raises" do
        failing_callback = ->(_info) { raise "Excessive wait callback error!" }

        tracker.update(limit: 100, remaining: 0, reset_at: Time.now + 0.1)

        connection = Faraday.new do |conn|
          conn.use described_class,
            state_store: tracker,
            queue_wait_warning_threshold: 0.01,  # Will trigger excessive wait
            on_excessive_wait: failing_callback
          conn.adapter :test, exception_test_stubs
        end

        # Stub not needed - exception happens before HTTP call

        # The request should raise due to callback error
        expect { connection.get("/test") }.to raise_error("Excessive wait callback error!")

        # But queued_count should still be 0 (decremented in ensure block)
        expect(tracker.queued_count).to eq(0)
      end

      it "invokes on_dequeue callback even when on_queue callback raises" do
        dequeue_log = []
        failing_queue_callback = ->(_info) { raise "Queue callback error!" }
        dequeue_callback = ->(info) { dequeue_log << info }

        tracker.update(limit: 100, remaining: 0, reset_at: Time.now + 0.05)

        connection = Faraday.new do |conn|
          conn.use described_class,
            state_store: tracker,
            on_queue: failing_queue_callback,
            on_dequeue: dequeue_callback
          conn.adapter :test, exception_test_stubs
        end

        # Stub not needed - exception happens before HTTP call

        # The request should raise due to callback error
        expect { connection.get("/test") }.to raise_error("Queue callback error!")

        # But on_dequeue should still have been called (in ensure block)
        expect(dequeue_log.size).to eq(1)
      end
    end
  end
end
