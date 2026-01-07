# frozen_string_literal: true

require "spec_helper"

RSpec.describe SecApi::RateLimitTracker do
  subject(:tracker) { described_class.new }

  describe "#initialize" do
    it "starts with nil state" do
      expect(tracker.current_state).to be_nil
    end
  end

  describe "#update" do
    it "stores rate limit state" do
      reset_time = Time.now + 60
      tracker.update(limit: 100, remaining: 95, reset_at: reset_time)

      state = tracker.current_state
      expect(state).to be_a(SecApi::RateLimitState)
      expect(state.limit).to eq(100)
      expect(state.remaining).to eq(95)
      expect(state.reset_at).to eq(reset_time)
    end

    it "replaces previous state on subsequent updates" do
      tracker.update(limit: 100, remaining: 95, reset_at: Time.now + 60)
      tracker.update(limit: 100, remaining: 90, reset_at: Time.now + 120)

      expect(tracker.current_state.remaining).to eq(90)
    end

    it "handles nil values" do
      tracker.update(limit: nil, remaining: nil, reset_at: nil)

      state = tracker.current_state
      expect(state.limit).to be_nil
      expect(state.remaining).to be_nil
      expect(state.reset_at).to be_nil
    end

    it "returns the created state" do
      result = tracker.update(limit: 100, remaining: 95, reset_at: Time.now)
      expect(result).to be_a(SecApi::RateLimitState)
      expect(result.limit).to eq(100)
    end
  end

  describe "#current_state" do
    it "returns nil when no state has been set" do
      expect(tracker.current_state).to be_nil
    end

    it "returns the most recent state" do
      tracker.update(limit: 100, remaining: 50, reset_at: Time.now)
      state = tracker.current_state

      expect(state.remaining).to eq(50)
    end

    it "returns an immutable RateLimitState" do
      tracker.update(limit: 100, remaining: 50, reset_at: Time.now)
      state = tracker.current_state

      expect(state).to be_frozen
    end
  end

  describe "#reset!" do
    it "clears the state" do
      tracker.update(limit: 100, remaining: 50, reset_at: Time.now)
      tracker.reset!

      expect(tracker.current_state).to be_nil
    end
  end

  describe "thread safety" do
    it "handles concurrent updates safely" do
      threads = 10.times.map do |i|
        Thread.new do
          tracker.update(limit: 100, remaining: 100 - i, reset_at: Time.now)
        end
      end
      threads.each(&:join)

      # Should have a valid state (any of the updates)
      state = tracker.current_state
      expect(state).not_to be_nil
      expect(state.limit).to eq(100)
      expect(state.remaining).to be_between(90, 100)
    end

    it "handles concurrent reads safely" do
      tracker.update(limit: 100, remaining: 50, reset_at: Time.now)

      threads = 20.times.map do
        Thread.new { tracker.current_state }
      end
      results = threads.map(&:value)

      # All reads should return valid state
      results.each do |state|
        expect(state).to be_a(SecApi::RateLimitState)
        expect(state.remaining).to eq(50)
      end
    end

    it "handles mixed reads and writes safely" do
      threads = []

      # Writers
      10.times do |i|
        threads << Thread.new do
          tracker.update(limit: 100, remaining: 100 - i, reset_at: Time.now)
        end
      end

      # Readers
      10.times do
        threads << Thread.new { tracker.current_state }
      end

      threads.each(&:join)

      # Final state should be valid
      state = tracker.current_state
      expect(state).to be_a(SecApi::RateLimitState)
    end
  end

  describe "instance independence" do
    it "maintains separate state per tracker instance" do
      tracker1 = described_class.new
      tracker2 = described_class.new

      tracker1.update(limit: 100, remaining: 50, reset_at: Time.now)
      tracker2.update(limit: 200, remaining: 150, reset_at: Time.now)

      expect(tracker1.current_state.limit).to eq(100)
      expect(tracker2.current_state.limit).to eq(200)
    end
  end
end
