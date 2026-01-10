# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Request ID flow integration" do
  let(:stubs) { Faraday::Adapter::Test::Stubs.new }
  let(:config) { SecApi::Config.new(api_key: "test_api_key_12345") }

  after { stubs.verify_stubbed_calls }

  describe "request_id consistency from Instrumentation through ErrorHandler" do
    it "uses same request_id in on_request callback and error" do
      stubs.get("/test") { [500, {}, "Server error"] }

      request_callback_id = nil
      error_id = nil

      config.on_request = ->(request_id:, **) { request_callback_id = request_id }

      connection = Faraday.new do |builder|
        builder.use SecApi::Middleware::Instrumentation, config: config
        builder.use SecApi::Middleware::ErrorHandler, config: config
        builder.adapter :test, stubs
      end

      begin
        connection.get("/test")
      rescue SecApi::ServerError => e
        error_id = e.request_id
      end

      expect(request_callback_id).not_to be_nil
      expect(error_id).to eq(request_callback_id)
    end

    it "includes request_id in error message that matches callback request_id" do
      stubs.get("/test") { [429, {"Retry-After" => "60"}, "Rate limited"] }

      request_callback_id = nil
      error = nil

      config.on_request = ->(request_id:, **) { request_callback_id = request_id }

      connection = Faraday.new do |builder|
        builder.use SecApi::Middleware::Instrumentation, config: config
        builder.use SecApi::Middleware::ErrorHandler, config: config
        builder.adapter :test, stubs
      end

      begin
        connection.get("/test")
      rescue SecApi::RateLimitError => e
        error = e
      end

      expect(request_callback_id).not_to be_nil
      expect(error.request_id).to eq(request_callback_id)
      expect(error.message).to include("[#{request_callback_id}]")
    end
  end

  describe "on_error callback receives same request_id as on_request" do
    it "passes matching request_id to both callbacks" do
      stubs.get("/test") { [401, {}, "Unauthorized"] }

      request_ids = {on_request: nil, on_error: nil}

      config.on_request = ->(request_id:, **) { request_ids[:on_request] = request_id }
      config.on_error = ->(request_id:, **) { request_ids[:on_error] = request_id }

      connection = Faraday.new do |builder|
        builder.use SecApi::Middleware::Instrumentation, config: config
        builder.use SecApi::Middleware::ErrorHandler, config: config
        builder.adapter :test, stubs
      end

      expect { connection.get("/test") }.to raise_error(SecApi::AuthenticationError)

      expect(request_ids[:on_request]).not_to be_nil
      expect(request_ids[:on_error]).to eq(request_ids[:on_request])
    end

    it "passes error with matching request_id to on_error callback" do
      stubs.get("/test") { [404, {}, "Not found"] }

      error_from_callback = nil

      config.on_error = ->(error:, **) { error_from_callback = error }

      connection = Faraday.new do |builder|
        builder.use SecApi::Middleware::Instrumentation, config: config
        builder.use SecApi::Middleware::ErrorHandler, config: config
        builder.adapter :test, stubs
      end

      raised_error = nil
      begin
        connection.get("/test")
      rescue SecApi::NotFoundError => e
        raised_error = e
      end

      expect(error_from_callback).to eq(raised_error)
      expect(error_from_callback.request_id).not_to be_nil
    end
  end

  describe "external request_id preserved through entire flow" do
    it "uses external request_id in all callbacks and errors" do
      stubs.get("/test") { [422, {}, "Unprocessable"] }

      external_id = "external-trace-#{SecureRandom.hex(8)}"
      captured_ids = {on_request: nil, on_error: nil, error: nil}

      config.on_request = ->(request_id:, **) { captured_ids[:on_request] = request_id }
      config.on_error = ->(request_id:, **) { captured_ids[:on_error] = request_id }

      # Custom middleware to inject external request_id
      external_id_middleware = Class.new(Faraday::Middleware) do
        def initialize(app, ext_id)
          super(app)
          @ext_id = ext_id
        end

        def call(env)
          env[:request_id] = @ext_id
          @app.call(env)
        end
      end

      connection = Faraday.new do |builder|
        builder.use external_id_middleware, external_id
        builder.use SecApi::Middleware::Instrumentation, config: config
        builder.use SecApi::Middleware::ErrorHandler, config: config
        builder.adapter :test, stubs
      end

      begin
        connection.get("/test")
      rescue SecApi::ValidationError => e
        captured_ids[:error] = e.request_id
      end

      # External ID should be preserved throughout
      expect(captured_ids[:on_request]).to eq(external_id)
      expect(captured_ids[:on_error]).to eq(external_id)
      expect(captured_ids[:error]).to eq(external_id)
    end

    it "includes external request_id in error message" do
      stubs.get("/test") { [403, {}, "Forbidden"] }

      external_id = "rails-request-abc123"

      # Custom middleware to inject external request_id
      external_id_middleware = Class.new(Faraday::Middleware) do
        def initialize(app, ext_id)
          super(app)
          @ext_id = ext_id
        end

        def call(env)
          env[:request_id] = @ext_id
          @app.call(env)
        end
      end

      connection = Faraday.new do |builder|
        builder.use external_id_middleware, external_id
        builder.use SecApi::Middleware::Instrumentation, config: config
        builder.use SecApi::Middleware::ErrorHandler, config: config
        builder.adapter :test, stubs
      end

      expect {
        connection.get("/test")
      }.to raise_error(SecApi::AuthenticationError) do |error|
        expect(error.request_id).to eq(external_id)
        expect(error.message).to include("[#{external_id}]")
      end
    end
  end

  describe "request_id with successful responses" do
    it "passes request_id to on_response callback" do
      stubs.get("/test") { [200, {}, '{"success": true}'] }

      response_callback_id = nil

      config.on_response = ->(request_id:, **) { response_callback_id = request_id }

      connection = Faraday.new do |builder|
        builder.use SecApi::Middleware::Instrumentation, config: config
        builder.use SecApi::Middleware::ErrorHandler, config: config
        builder.adapter :test, stubs
      end

      connection.get("/test")

      expect(response_callback_id).not_to be_nil
      expect(response_callback_id).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i)
    end

    it "uses same request_id in on_request and on_response callbacks" do
      stubs.get("/test") { [200, {}, '{"success": true}'] }

      captured_ids = {on_request: nil, on_response: nil}

      config.on_request = ->(request_id:, **) { captured_ids[:on_request] = request_id }
      config.on_response = ->(request_id:, **) { captured_ids[:on_response] = request_id }

      connection = Faraday.new do |builder|
        builder.use SecApi::Middleware::Instrumentation, config: config
        builder.use SecApi::Middleware::ErrorHandler, config: config
        builder.adapter :test, stubs
      end

      connection.get("/test")

      expect(captured_ids[:on_request]).not_to be_nil
      expect(captured_ids[:on_response]).to eq(captured_ids[:on_request])
    end
  end
end
