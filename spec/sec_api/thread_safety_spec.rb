# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Request ID thread safety" do
  describe "concurrent request_id generation" do
    it "generates unique request_id per concurrent request" do
      stubs = Faraday::Adapter::Test::Stubs.new
      stubs.get("/test") { [200, {}, '{"success": true}'] }

      request_ids = Queue.new
      mutex = Mutex.new
      config = SecApi::Config.new(api_key: "test_api_key_12345")

      # Track request_ids via on_request callback
      config.on_request = lambda { |request_id:, **|
        mutex.synchronize { request_ids << request_id }
      }

      connection = Faraday.new do |builder|
        builder.use SecApi::Middleware::Instrumentation, config: config
        builder.adapter :test, stubs
      end

      # Spawn 10 concurrent threads
      thread_count = 10
      threads = thread_count.times.map do
        Thread.new { connection.get("/test") }
      end
      threads.each(&:join)

      # Collect all request_ids
      collected_ids = []
      collected_ids << request_ids.pop until request_ids.empty?

      # All request IDs should be unique (no collisions)
      expect(collected_ids.size).to eq(thread_count)
      expect(collected_ids.uniq.size).to eq(thread_count)

      # All should be valid UUIDs
      collected_ids.each do |id|
        expect(id).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i)
      end
    end

    it "preserves external request_ids across concurrent threads" do
      stubs = Faraday::Adapter::Test::Stubs.new
      stubs.get("/test") { [200, {}, '{"success": true}'] }

      received_ids = Queue.new
      mutex = Mutex.new
      config = SecApi::Config.new(api_key: "test_api_key_12345")

      # Track request_ids via on_request callback
      config.on_request = lambda { |request_id:, **|
        mutex.synchronize { received_ids << request_id }
      }

      # Custom middleware to inject external request_id
      external_id_middleware = Class.new(Faraday::Middleware) do
        def initialize(app, external_id)
          super(app)
          @external_id = external_id
        end

        def call(env)
          env[:request_id] = @external_id
          @app.call(env)
        end
      end

      # Generate unique external IDs for each thread
      thread_count = 10
      external_ids = thread_count.times.map { |i| "external-thread-#{i}-#{SecureRandom.hex(4)}" }

      threads = thread_count.times.map do |i|
        Thread.new do
          connection = Faraday.new do |builder|
            builder.use external_id_middleware, external_ids[i]
            builder.use SecApi::Middleware::Instrumentation, config: config
            builder.adapter :test, stubs
          end
          connection.get("/test")
        end
      end
      threads.each(&:join)

      # Collect received IDs
      collected_ids = []
      collected_ids << received_ids.pop until received_ids.empty?

      # All external IDs should be preserved
      expect(collected_ids.size).to eq(thread_count)
      expect(collected_ids.sort).to eq(external_ids.sort)
    end

    it "includes request_id in errors raised from concurrent threads" do
      stubs = Faraday::Adapter::Test::Stubs.new
      stubs.get("/test") { [429, {"Retry-After" => "60"}, "Rate limited"] }

      config = SecApi::Config.new(api_key: "test_api_key_12345")
      error_request_ids = Queue.new
      mutex = Mutex.new

      connection = Faraday.new do |builder|
        builder.use SecApi::Middleware::Instrumentation, config: config
        builder.use SecApi::Middleware::ErrorHandler, config: config
        builder.adapter :test, stubs
      end

      # Spawn concurrent threads that will all get rate limited
      thread_count = 5
      threads = thread_count.times.map do
        Thread.new do
          connection.get("/test")
        rescue SecApi::RateLimitError => e
          mutex.synchronize { error_request_ids << e.request_id }
        end
      end
      threads.each(&:join)

      # Collect error request_ids
      collected_ids = []
      collected_ids << error_request_ids.pop until error_request_ids.empty?

      # Each error should have a unique request_id
      expect(collected_ids.size).to eq(thread_count)
      expect(collected_ids.uniq.size).to eq(thread_count)

      # All should be valid UUIDs
      collected_ids.each do |id|
        expect(id).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i)
      end
    end

    it "maintains request_id consistency from request to error in concurrent threads" do
      stubs = Faraday::Adapter::Test::Stubs.new
      stubs.get("/test") { [500, {}, "Server error"] }

      config = SecApi::Config.new(api_key: "test_api_key_12345")

      request_error_pairs = Queue.new
      mutex = Mutex.new

      # Track both request_id from callback and error
      config.on_request = lambda { |request_id:, **|
        Thread.current[:test_request_id] = request_id
      }

      connection = Faraday.new do |builder|
        builder.use SecApi::Middleware::Instrumentation, config: config
        builder.use SecApi::Middleware::ErrorHandler, config: config
        builder.adapter :test, stubs
      end

      thread_count = 5
      threads = thread_count.times.map do
        Thread.new do
          connection.get("/test")
        rescue SecApi::ServerError => e
          mutex.synchronize do
            request_error_pairs << {
              request_id: Thread.current[:test_request_id],
              error_request_id: e.request_id
            }
          end
        end
      end
      threads.each(&:join)

      # Collect pairs
      pairs = []
      pairs << request_error_pairs.pop until request_error_pairs.empty?

      # Each pair should have matching request_ids
      expect(pairs.size).to eq(thread_count)
      pairs.each do |pair|
        expect(pair[:request_id]).to eq(pair[:error_request_id])
        expect(pair[:request_id]).not_to be_nil
      end

      # All request_ids should be unique across threads
      all_request_ids = pairs.map { |p| p[:request_id] }
      expect(all_request_ids.uniq.size).to eq(thread_count)
    end
  end
end
