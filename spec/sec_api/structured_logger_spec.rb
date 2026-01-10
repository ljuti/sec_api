# frozen_string_literal: true

require "spec_helper"
require "json"

RSpec.describe SecApi::StructuredLogger do
  let(:logger) { instance_double(Logger) }
  let(:output) { [] }

  before do
    allow(logger).to receive(:debug) { |&block| output << JSON.parse(block.call) }
    allow(logger).to receive(:info) { |&block| output << JSON.parse(block.call) }
    allow(logger).to receive(:warn) { |&block| output << JSON.parse(block.call) }
    allow(logger).to receive(:error) { |&block| output << JSON.parse(block.call) }
  end

  describe ".log_request" do
    it "logs request start event with correct fields" do
      described_class.log_request(logger, :info,
        request_id: "abc-123",
        method: :get,
        url: "https://api.sec-api.io/query")

      expect(output.first).to include(
        "event" => "secapi.request.start",
        "request_id" => "abc-123",
        "method" => "GET",
        "url" => "https://api.sec-api.io/query"
      )
    end

    it "includes timestamp in ISO8601 format with milliseconds" do
      described_class.log_request(logger, :info,
        request_id: "abc-123",
        method: :get,
        url: "https://api.sec-api.io/query")

      expect(output.first).to have_key("timestamp")
      expect(output.first["timestamp"]).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z/)
    end

    it "converts HTTP method to uppercase" do
      described_class.log_request(logger, :info,
        request_id: "abc-123",
        method: :post,
        url: "https://api.sec-api.io/query")

      expect(output.first["method"]).to eq("POST")
    end

    it "uses the specified log level" do
      expect(logger).to receive(:debug) { |&block| output << JSON.parse(block.call) }

      described_class.log_request(logger, :debug,
        request_id: "abc-123",
        method: :get,
        url: "https://api.sec-api.io/query")
    end
  end

  describe ".log_response" do
    it "logs request complete event with correct fields" do
      described_class.log_response(logger, :info,
        request_id: "abc-123",
        status: 200,
        duration_ms: 150,
        url: "https://api.sec-api.io/query",
        method: :get)

      expect(output.first).to include(
        "event" => "secapi.request.complete",
        "request_id" => "abc-123",
        "status" => 200,
        "duration_ms" => 150,
        "method" => "GET",
        "url" => "https://api.sec-api.io/query"
      )
    end

    it "includes success flag based on status code" do
      described_class.log_response(logger, :info,
        request_id: "abc-123",
        status: 200,
        duration_ms: 150,
        url: "https://api.sec-api.io/query",
        method: :get)

      expect(output.first["success"]).to eq(true)
    end

    it "marks success false for 4xx status codes" do
      described_class.log_response(logger, :info,
        request_id: "abc-123",
        status: 404,
        duration_ms: 150,
        url: "https://api.sec-api.io/query",
        method: :get)

      expect(output.first["success"]).to eq(false)
    end

    it "marks success false for 5xx status codes" do
      described_class.log_response(logger, :info,
        request_id: "abc-123",
        status: 500,
        duration_ms: 150,
        url: "https://api.sec-api.io/query",
        method: :get)

      expect(output.first["success"]).to eq(false)
    end

    it "includes timestamp" do
      described_class.log_response(logger, :info,
        request_id: "abc-123",
        status: 200,
        duration_ms: 150,
        url: "https://api.sec-api.io/query",
        method: :get)

      expect(output.first).to have_key("timestamp")
    end
  end

  describe ".log_retry" do
    it "logs retry event with correct fields" do
      described_class.log_retry(logger, :warn,
        request_id: "abc-123",
        attempt: 2,
        max_attempts: 5,
        error_class: "SecApi::ServerError",
        error_message: "Internal Server Error",
        will_retry_in: 4.0)

      expect(output.first).to include(
        "event" => "secapi.request.retry",
        "request_id" => "abc-123",
        "attempt" => 2,
        "max_attempts" => 5,
        "error_class" => "SecApi::ServerError",
        "error_message" => "Internal Server Error",
        "will_retry_in" => 4.0
      )
    end

    it "includes timestamp" do
      described_class.log_retry(logger, :warn,
        request_id: "abc-123",
        attempt: 1,
        max_attempts: 3,
        error_class: "SecApi::NetworkError",
        error_message: "Connection failed",
        will_retry_in: 1.0)

      expect(output.first).to have_key("timestamp")
    end
  end

  describe ".log_error" do
    let(:error) { SecApi::AuthenticationError.new("Invalid API key") }

    it "logs error event with correct fields" do
      described_class.log_error(logger, :error,
        request_id: "abc-123",
        error: error,
        url: "https://api.sec-api.io/query",
        method: :get)

      expect(output.first).to include(
        "event" => "secapi.request.error",
        "request_id" => "abc-123",
        "error_class" => "SecApi::AuthenticationError",
        "error_message" => "Invalid API key",
        "method" => "GET",
        "url" => "https://api.sec-api.io/query"
      )
    end

    it "includes timestamp" do
      described_class.log_error(logger, :error,
        request_id: "abc-123",
        error: error,
        url: "https://api.sec-api.io/query",
        method: :get)

      expect(output.first).to have_key("timestamp")
    end
  end

  describe "error safety" do
    it "does not raise when logger method fails" do
      allow(logger).to receive(:info).and_raise(StandardError, "Logger broken")

      expect {
        described_class.log_request(logger, :info,
          request_id: "abc-123",
          method: :get,
          url: "https://api.sec-api.io/query")
      }.not_to raise_error
    end

    it "does not raise when logger block evaluation fails" do
      # Simulate logger that raises during block evaluation
      failing_logger = instance_double(Logger)
      allow(failing_logger).to receive(:info) do |&block|
        block.call # Evaluate the block
        raise StandardError, "Write failed"
      end

      expect {
        described_class.log_request(failing_logger, :info,
          request_id: "abc-123",
          method: :get,
          url: "https://api.sec-api.io/query")
      }.not_to raise_error
    end

    it "does not propagate errors from any log level" do
      [:debug, :info, :warn, :error].each do |level|
        allow(logger).to receive(level).and_raise(StandardError, "Logger broken")

        expect {
          described_class.log_request(logger, level,
            request_id: "abc-123",
            method: :get,
            url: "https://api.sec-api.io/query")
        }.not_to raise_error
      end
    end
  end

  describe "event naming convention" do
    it "uses secapi.request.start for request events" do
      described_class.log_request(logger, :info,
        request_id: "abc-123",
        method: :get,
        url: "https://api.sec-api.io/query")

      expect(output.first["event"]).to eq("secapi.request.start")
    end

    it "uses secapi.request.complete for response events" do
      described_class.log_response(logger, :info,
        request_id: "abc-123",
        status: 200,
        duration_ms: 150,
        url: "https://api.sec-api.io/query",
        method: :get)

      expect(output.first["event"]).to eq("secapi.request.complete")
    end

    it "uses secapi.request.retry for retry events" do
      described_class.log_retry(logger, :warn,
        request_id: "abc-123",
        attempt: 1,
        max_attempts: 3,
        error_class: "SecApi::ServerError",
        error_message: "Error",
        will_retry_in: 1.0)

      expect(output.first["event"]).to eq("secapi.request.retry")
    end

    it "uses secapi.request.error for error events" do
      described_class.log_error(logger, :error,
        request_id: "abc-123",
        error: StandardError.new("Test"),
        url: "https://api.sec-api.io/query",
        method: :get)

      expect(output.first["event"]).to eq("secapi.request.error")
    end
  end
end
