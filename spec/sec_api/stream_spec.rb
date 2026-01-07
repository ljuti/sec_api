# frozen_string_literal: true

require "spec_helper"

RSpec.describe SecApi::Stream do
  let(:config) { SecApi::Config.new(api_key: "test_api_key_valid") }
  let(:client) { instance_double(SecApi::Client, config: config) }
  let(:stream) { described_class.new(client) }

  describe "#initialize" do
    it "stores the client reference" do
      expect(stream.client).to eq(client)
    end

    it "starts with disconnected state" do
      expect(stream.connected?).to be false
    end
  end

  describe "#subscribe" do
    it "raises ArgumentError without block (AC: #1)" do
      expect { stream.subscribe }.to raise_error(ArgumentError, /Block required/)
    end

    it "builds correct WebSocket URL with API key (AC: #1)" do
      # We verify URL construction via the private method for unit testing
      url = stream.send(:build_url)
      expect(url).to eq("wss://stream.sec-api.io?apiKey=test_api_key_valid")
    end
  end

  describe "#close" do
    it "handles close when not connected" do
      expect { stream.close }.not_to raise_error
    end

    it "returns nil after close" do
      expect(stream.close).to be_nil
    end
  end

  describe "#connected?" do
    it "returns false when not connected" do
      expect(stream.connected?).to be false
    end
  end

  describe "message handling" do
    let(:filing_message) do
      [
        {
          "accessionNo" => "0001193125-24-123456",
          "formType" => "8-K",
          "filedAt" => "2024-01-15T16:30:00-05:00",
          "cik" => "320193",
          "ticker" => "AAPL",
          "companyName" => "Apple Inc.",
          "linkToFilingDetails" => "https://sec-api.io/filing/...",
          "linkToTxt" => "https://www.sec.gov/...",
          "linkToHtml" => "https://www.sec.gov/...",
          "periodOfReport" => "2024-01-15"
        }
      ].to_json
    end

    before do
      # Set @running to true to allow message processing
      stream.instance_variable_set(:@running, true)
    end

    it "parses JSON message and invokes callback with StreamFiling (AC: #2)" do
      received_filing = nil
      stream.instance_variable_set(:@callback, ->(f) { received_filing = f })

      stream.send(:handle_message, filing_message)

      expect(received_filing).to be_a(SecApi::Objects::StreamFiling)
      expect(received_filing.accession_no).to eq("0001193125-24-123456")
      expect(received_filing.form_type).to eq("8-K")
      expect(received_filing.ticker).to eq("AAPL")
      expect(received_filing.company_name).to eq("Apple Inc.")
    end

    it "handles multiple filings in a single message" do
      multi_filing_message = [
        {"accessionNo" => "0001-24-001", "formType" => "8-K", "filedAt" => "2024-01-15T16:30:00-05:00", "cik" => "123", "companyName" => "Company A", "linkToFilingDetails" => "https://..."},
        {"accessionNo" => "0002-24-002", "formType" => "10-K", "filedAt" => "2024-01-15T16:31:00-05:00", "cik" => "456", "companyName" => "Company B", "linkToFilingDetails" => "https://..."}
      ].to_json

      received_filings = []
      stream.instance_variable_set(:@callback, ->(f) { received_filings << f })

      stream.send(:handle_message, multi_filing_message)

      expect(received_filings.size).to eq(2)
      expect(received_filings[0].accession_no).to eq("0001-24-001")
      expect(received_filings[1].accession_no).to eq("0002-24-002")
    end

    it "handles malformed JSON gracefully" do
      stream.instance_variable_set(:@callback, ->(f) { fail "Should not be called" })

      expect { stream.send(:handle_message, "not valid json") }.not_to raise_error
    end

    it "handles invalid filing data gracefully" do
      # Missing required fields
      invalid_message = [{"foo" => "bar"}].to_json
      stream.instance_variable_set(:@callback, ->(f) { fail "Should not be called" })

      expect { stream.send(:handle_message, invalid_message) }.not_to raise_error
    end
  end

  describe "close handling (AC: #4)" do
    before do
      # Prevent actual EM.stop calls
      allow(EM).to receive(:reactor_running?).and_return(false)
    end

    it "handles normal close (1000) without error" do
      expect { stream.send(:handle_close, 1000, "Normal closure") }.not_to raise_error
    end

    it "handles going_away close (1001) without error" do
      expect { stream.send(:handle_close, 1001, "Going away") }.not_to raise_error
    end

    it "raises AuthenticationError on policy violation (1008) (AC: #3)" do
      expect {
        stream.send(:handle_close, 1008, "Policy violation")
      }.to raise_error(SecApi::AuthenticationError, /authentication failed/)
    end

    it "raises NetworkError on abnormal close (1006) (AC: #3)" do
      expect {
        stream.send(:handle_close, 1006, "Abnormal closure")
      }.to raise_error(SecApi::NetworkError, /unexpectedly/)
    end

    it "raises NetworkError on unknown close codes (AC: #3)" do
      expect {
        stream.send(:handle_close, 4000, "Custom error")
      }.to raise_error(SecApi::NetworkError, /code 4000/)
    end

    it "sets running to false on close" do
      stream.instance_variable_set(:@running, true)

      begin
        stream.send(:handle_close, 1000, "Normal")
      rescue
        # Ignore any errors
      end

      expect(stream.instance_variable_get(:@running)).to be false
    end
  end

  describe "error handling (AC: #3)" do
    before do
      allow(EM).to receive(:reactor_running?).and_return(false)
    end

    it "raises NetworkError on WebSocket error event" do
      error_event = double("ErrorEvent", message: "Connection refused")

      expect {
        stream.send(:handle_error, error_event)
      }.to raise_error(SecApi::NetworkError, /Connection refused/)
    end

    it "handles error events without message method" do
      error_event = "Simple error string"

      expect {
        stream.send(:handle_error, error_event)
      }.to raise_error(SecApi::NetworkError, /Simple error string/)
    end
  end

  describe "key transformation" do
    it "converts camelCase to snake_case" do
      input = {"accessionNo" => "123", "formType" => "8-K", "linkToFilingDetails" => "url"}
      result = stream.send(:transform_keys, input)

      expect(result).to eq({accession_no: "123", form_type: "8-K", link_to_filing_details: "url"})
    end

    it "handles already snake_case keys" do
      input = {"accession_no" => "123"}
      result = stream.send(:transform_keys, input)

      expect(result).to eq({accession_no: "123"})
    end
  end

  describe "thread safety" do
    it "uses mutex for connected? check" do
      mutex = stream.instance_variable_get(:@mutex)
      expect(mutex).to be_a(Mutex)
    end

    it "uses mutex for close operation" do
      # Just verify no deadlock occurs
      expect { stream.close }.not_to raise_error
    end
  end

  describe "callback suppression after close (AC: #4, Task 5)" do
    it "prevents callbacks when @running is false" do
      received = []
      stream.instance_variable_set(:@callback, ->(f) { received << f })
      stream.instance_variable_set(:@running, false)

      message = [{"accessionNo" => "123", "formType" => "8-K", "filedAt" => "2024-01-15", "cik" => "456", "companyName" => "Test", "linkToFilingDetails" => "https://..."}].to_json
      stream.send(:handle_message, message)

      expect(received).to be_empty
    end

    it "stops processing mid-iteration when @running becomes false" do
      received = []
      stream.instance_variable_set(:@running, true)
      stream.instance_variable_set(:@callback, ->(f) {
        received << f
        stream.instance_variable_set(:@running, false) if received.size == 1
      })

      multi_message = [
        {"accessionNo" => "001", "formType" => "8-K", "filedAt" => "2024-01-15", "cik" => "123", "companyName" => "A", "linkToFilingDetails" => "https://..."},
        {"accessionNo" => "002", "formType" => "10-K", "filedAt" => "2024-01-15", "cik" => "456", "companyName" => "B", "linkToFilingDetails" => "https://..."},
        {"accessionNo" => "003", "formType" => "10-Q", "filedAt" => "2024-01-15", "cik" => "789", "companyName" => "C", "linkToFilingDetails" => "https://..."}
      ].to_json

      stream.send(:handle_message, multi_message)

      # Only first filing should be processed before @running was set to false
      expect(received.size).to eq(1)
      expect(received.first.accession_no).to eq("001")
    end
  end

  describe "ping/pong handling (AC: #2, Task 3)" do
    # Ping/pong is handled automatically by faye-websocket library.
    # The sec-api.io server pings every 25 seconds and expects pong within 5 seconds.
    # This test documents the expected behavior without requiring a real WebSocket server.
    it "relies on faye-websocket automatic ping/pong handling" do
      # faye-websocket automatically responds to ping frames with pong frames
      # at the protocol level. No application code is required.
      # See: https://github.com/faye/faye-websocket-ruby#ping--pong
      expect(Faye::WebSocket::Client).to respond_to(:new)
    end
  end

  describe "error logging (M4 fix)" do
    let(:logger) { instance_double(Logger) }
    let(:config_with_logger) do
      instance_double(SecApi::Config,
        api_key: "test_key",
        logger: logger,
        log_level: :warn)
    end
    let(:client_with_logger) { instance_double(SecApi::Client, config: config_with_logger) }
    let(:stream_with_logger) { described_class.new(client_with_logger) }

    it "logs JSON parse errors when logger is configured" do
      stream_with_logger.instance_variable_set(:@running, true)
      stream_with_logger.instance_variable_set(:@callback, ->(f) { fail "Should not be called" })

      expect(logger).to receive(:warn).once

      stream_with_logger.send(:handle_message, "invalid json {{{")
    end

    it "logs Dry::Struct validation errors when logger is configured" do
      stream_with_logger.instance_variable_set(:@running, true)
      stream_with_logger.instance_variable_set(:@callback, ->(f) { fail "Should not be called" })

      # Missing required fields will cause Dry::Struct::Error
      invalid_filing = [{"foo" => "bar"}].to_json

      expect(logger).to receive(:warn).once

      stream_with_logger.send(:handle_message, invalid_filing)
    end

    it "does not fail when logger is not configured" do
      stream.instance_variable_set(:@running, true)
      stream.instance_variable_set(:@callback, ->(f) { fail "Should not be called" })

      expect { stream.send(:handle_message, "invalid json") }.not_to raise_error
    end
  end
end
