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

    describe "reconnection prevention (Story 6.4, Task 9)" do
      it "sets should_reconnect to false" do
        expect(stream.instance_variable_get(:@should_reconnect)).to be true

        stream.close

        expect(stream.instance_variable_get(:@should_reconnect)).to be false
      end

      it "is idempotent" do
        stream.close
        expect { stream.close }.not_to raise_error
        expect { stream.close }.not_to raise_error
      end

      it "prevents auto-reconnect after abnormal close" do
        allow(EM).to receive(:reactor_running?).and_return(true)
        allow(EM).to receive(:stop_event_loop)
        allow(EM).to receive(:add_timer)

        # User closes the stream
        stream.close

        # Simulate abnormal close event
        stream.instance_variable_set(:@running, true)
        expect(stream).not_to receive(:schedule_reconnect)

        expect {
          stream.send(:handle_close, 1006, "Abnormal closure")
        }.to raise_error(SecApi::NetworkError)
      end
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

  describe "#subscribe with filter parameters (Story 6.2)" do
    describe "method signature" do
      before do
        allow(stream).to receive(:connect)
      end

      it "accepts tickers keyword argument" do
        expect { stream.subscribe(tickers: ["AAPL"]) { |f| } }.not_to raise_error
      end

      it "accepts form_types keyword argument" do
        expect { stream.subscribe(form_types: ["10-K"]) { |f| } }.not_to raise_error
      end

      it "accepts both tickers and form_types together" do
        expect { stream.subscribe(tickers: ["AAPL"], form_types: ["10-K"]) { |f| } }.not_to raise_error
      end

      it "stores normalized tickers filter (uppercase)" do
        stream.subscribe(tickers: ["aapl", "TSLA"]) { |f| }
        expect(stream.instance_variable_get(:@tickers)).to eq(["AAPL", "TSLA"])
      end

      it "stores normalized form_types filter (uppercase)" do
        stream.subscribe(form_types: ["10-k", "8-K"]) { |f| }
        expect(stream.instance_variable_get(:@form_types)).to eq(["10-K", "8-K"])
      end

      it "treats empty array as nil (no filter)" do
        stream.subscribe(tickers: [], form_types: []) { |f| }
        expect(stream.instance_variable_get(:@tickers)).to be_nil
        expect(stream.instance_variable_get(:@form_types)).to be_nil
      end

      it "accepts single string ticker (convenience)" do
        stream.subscribe(tickers: "AAPL") { |f| }
        expect(stream.instance_variable_get(:@tickers)).to eq(["AAPL"])
      end

      it "accepts single string form_type (convenience)" do
        stream.subscribe(form_types: "10-K") { |f| }
        expect(stream.instance_variable_get(:@form_types)).to eq(["10-K"])
      end

      it "deduplicates filter values" do
        stream.subscribe(tickers: ["AAPL", "aapl", "AAPL"]) { |f| }
        expect(stream.instance_variable_get(:@tickers)).to eq(["AAPL"])
      end

      it "deduplicates form_types filter values" do
        stream.subscribe(form_types: ["10-K", "10-k", "10-K"]) { |f| }
        expect(stream.instance_variable_get(:@form_types)).to eq(["10-K"])
      end

      it "maintains backwards compatibility (no args)" do
        stream.subscribe { |f| }
        expect(stream.instance_variable_get(:@tickers)).to be_nil
        expect(stream.instance_variable_get(:@form_types)).to be_nil
      end
    end

    describe "ticker filtering (AC: #1)" do
      let(:aapl_filing) do
        {"accessionNo" => "001", "formType" => "10-K", "filedAt" => "2024-01-15", "cik" => "320193", "ticker" => "AAPL", "companyName" => "Apple Inc.", "linkToFilingDetails" => "https://..."}
      end
      let(:tsla_filing) do
        {"accessionNo" => "002", "formType" => "8-K", "filedAt" => "2024-01-15", "cik" => "1318605", "ticker" => "TSLA", "companyName" => "Tesla Inc.", "linkToFilingDetails" => "https://..."}
      end
      let(:msft_filing) do
        {"accessionNo" => "003", "formType" => "10-Q", "filedAt" => "2024-01-15", "cik" => "789019", "ticker" => "MSFT", "companyName" => "Microsoft Corp.", "linkToFilingDetails" => "https://..."}
      end

      before do
        allow(stream).to receive(:connect)
        stream.instance_variable_set(:@running, true)
      end

      it "delivers only matching ticker filings" do
        received = []
        stream.subscribe(tickers: ["AAPL"]) { |f| received << f }
        stream.send(:handle_message, [aapl_filing, tsla_filing, msft_filing].to_json)

        expect(received.size).to eq(1)
        expect(received.first.ticker).to eq("AAPL")
      end

      it "matches multiple tickers" do
        received = []
        stream.subscribe(tickers: ["AAPL", "TSLA"]) { |f| received << f }
        stream.send(:handle_message, [aapl_filing, tsla_filing, msft_filing].to_json)

        expect(received.size).to eq(2)
        expect(received.map(&:ticker)).to contain_exactly("AAPL", "TSLA")
      end

      it "is case-insensitive" do
        received = []
        stream.subscribe(tickers: ["aapl"]) { |f| received << f }
        stream.send(:handle_message, [aapl_filing].to_json)

        expect(received.size).to eq(1)
      end

      it "handles nil ticker in filing (passes through)" do
        no_ticker_filing = {"accessionNo" => "004", "formType" => "8-K", "filedAt" => "2024-01-15", "cik" => "123456", "companyName" => "No Ticker Corp.", "linkToFilingDetails" => "https://..."}
        received = []
        stream.subscribe(tickers: ["AAPL"]) { |f| received << f }
        stream.send(:handle_message, [no_ticker_filing].to_json)

        expect(received.size).to eq(1)  # nil ticker passes through
      end

      it "passes all filings when no ticker filter" do
        received = []
        stream.subscribe { |f| received << f }
        stream.send(:handle_message, [aapl_filing, tsla_filing, msft_filing].to_json)

        expect(received.size).to eq(3)
      end
    end

    describe "form_type filtering (AC: #2)" do
      let(:filing_10k) do
        {"accessionNo" => "001", "formType" => "10-K", "filedAt" => "2024-01-15", "cik" => "320193", "ticker" => "AAPL", "companyName" => "Apple Inc.", "linkToFilingDetails" => "https://..."}
      end
      let(:filing_8k) do
        {"accessionNo" => "002", "formType" => "8-K", "filedAt" => "2024-01-15", "cik" => "320193", "ticker" => "AAPL", "companyName" => "Apple Inc.", "linkToFilingDetails" => "https://..."}
      end
      let(:filing_10q) do
        {"accessionNo" => "003", "formType" => "10-Q", "filedAt" => "2024-01-15", "cik" => "320193", "ticker" => "AAPL", "companyName" => "Apple Inc.", "linkToFilingDetails" => "https://..."}
      end
      let(:filing_10ka) do
        {"accessionNo" => "004", "formType" => "10-K/A", "filedAt" => "2024-01-15", "cik" => "320193", "ticker" => "AAPL", "companyName" => "Apple Inc.", "linkToFilingDetails" => "https://..."}
      end

      before do
        allow(stream).to receive(:connect)
        stream.instance_variable_set(:@running, true)
      end

      it "delivers only matching form type filings" do
        received = []
        stream.subscribe(form_types: ["10-K"]) { |f| received << f }
        stream.send(:handle_message, [filing_10k, filing_8k, filing_10q].to_json)

        expect(received.size).to eq(1)
        expect(received.first.form_type).to eq("10-K")
      end

      it "matches multiple form types" do
        received = []
        stream.subscribe(form_types: ["10-K", "8-K"]) { |f| received << f }
        stream.send(:handle_message, [filing_10k, filing_8k, filing_10q].to_json)

        expect(received.size).to eq(2)
        expect(received.map(&:form_type)).to contain_exactly("10-K", "8-K")
      end

      it "is case-insensitive" do
        received = []
        stream.subscribe(form_types: ["10-k"]) { |f| received << f }
        stream.send(:handle_message, [filing_10k].to_json)

        expect(received.size).to eq(1)
      end

      it "matches amendments (10-K/A matches 10-K filter)" do
        received = []
        stream.subscribe(form_types: ["10-K"]) { |f| received << f }
        stream.send(:handle_message, [filing_10k, filing_10ka].to_json)

        expect(received.size).to eq(2)
        expect(received.map(&:form_type)).to contain_exactly("10-K", "10-K/A")
      end

      it "does not match 10-K when filtering for 10-K/A only" do
        received = []
        stream.subscribe(form_types: ["10-K/A"]) { |f| received << f }
        stream.send(:handle_message, [filing_10k, filing_10ka].to_json)

        expect(received.size).to eq(1)
        expect(received.first.form_type).to eq("10-K/A")
      end

      it "filters out filings with nil form_type" do
        no_form_filing = {"accessionNo" => "005", "filedAt" => "2024-01-15", "cik" => "123456", "companyName" => "Unknown Corp.", "linkToFilingDetails" => "https://..."}
        received = []
        stream.subscribe(form_types: ["10-K"]) { |f| received << f }
        stream.send(:handle_message, [no_form_filing].to_json)

        expect(received.size).to eq(0)
      end

      it "passes all filings when no form_type filter" do
        received = []
        stream.subscribe { |f| received << f }
        stream.send(:handle_message, [filing_10k, filing_8k, filing_10q].to_json)

        expect(received.size).to eq(3)
      end
    end

    describe "combined filtering (AC: #3)" do
      let(:aapl_10k) do
        {"accessionNo" => "001", "formType" => "10-K", "filedAt" => "2024-01-15", "cik" => "320193", "ticker" => "AAPL", "companyName" => "Apple Inc.", "linkToFilingDetails" => "https://..."}
      end
      let(:aapl_8k) do
        {"accessionNo" => "002", "formType" => "8-K", "filedAt" => "2024-01-15", "cik" => "320193", "ticker" => "AAPL", "companyName" => "Apple Inc.", "linkToFilingDetails" => "https://..."}
      end
      let(:tsla_10k) do
        {"accessionNo" => "003", "formType" => "10-K", "filedAt" => "2024-01-15", "cik" => "1318605", "ticker" => "TSLA", "companyName" => "Tesla Inc.", "linkToFilingDetails" => "https://..."}
      end
      let(:msft_8k) do
        {"accessionNo" => "004", "formType" => "8-K", "filedAt" => "2024-01-15", "cik" => "789019", "ticker" => "MSFT", "companyName" => "Microsoft Corp.", "linkToFilingDetails" => "https://..."}
      end

      before do
        allow(stream).to receive(:connect)
        stream.instance_variable_set(:@running, true)
      end

      it "applies AND logic for ticker and form_type filters" do
        received = []
        stream.subscribe(tickers: ["AAPL"], form_types: ["10-K"]) { |f| received << f }
        stream.send(:handle_message, [aapl_10k, aapl_8k, tsla_10k, msft_8k].to_json)

        expect(received.size).to eq(1)
        expect(received.first.ticker).to eq("AAPL")
        expect(received.first.form_type).to eq("10-K")
      end

      it "applies AND logic with multiple values in each filter" do
        received = []
        stream.subscribe(tickers: ["AAPL", "TSLA"], form_types: ["10-K", "10-Q"]) { |f| received << f }
        stream.send(:handle_message, [aapl_10k, aapl_8k, tsla_10k, msft_8k].to_json)

        expect(received.size).to eq(2)
        expect(received.map(&:ticker)).to contain_exactly("AAPL", "TSLA")
        expect(received.map(&:form_type)).to all(eq("10-K"))
      end

      it "uses matches_filters? for combined check" do
        allow(stream).to receive(:connect)
        stream.subscribe(tickers: ["AAPL"], form_types: ["10-K"]) { |f| }

        filing = SecApi::Objects::StreamFiling.new(
          accession_no: "001",
          form_type: "10-K",
          filed_at: "2024-01-15",
          cik: "320193",
          ticker: "AAPL",
          company_name: "Apple Inc.",
          link_to_filing_details: "https://..."
        )
        non_matching = SecApi::Objects::StreamFiling.new(
          accession_no: "002",
          form_type: "8-K",
          filed_at: "2024-01-15",
          cik: "320193",
          ticker: "AAPL",
          company_name: "Apple Inc.",
          link_to_filing_details: "https://..."
        )

        expect(stream.send(:matches_filters?, filing)).to be true
        expect(stream.send(:matches_filters?, non_matching)).to be false
      end
    end

    describe "#filters method (AC: #5)" do
      before do
        allow(stream).to receive(:connect)
      end

      it "returns current filter configuration with tickers" do
        stream.subscribe(tickers: ["AAPL", "TSLA"]) { |f| }
        expect(stream.filters).to eq({tickers: ["AAPL", "TSLA"], form_types: nil})
      end

      it "returns current filter configuration with form_types" do
        stream.subscribe(form_types: ["10-K", "8-K"]) { |f| }
        expect(stream.filters).to eq({tickers: nil, form_types: ["10-K", "8-K"]})
      end

      it "returns current filter configuration with both" do
        stream.subscribe(tickers: ["AAPL"], form_types: ["10-K"]) { |f| }
        expect(stream.filters).to eq({tickers: ["AAPL"], form_types: ["10-K"]})
      end

      it "returns nil values when no filters configured" do
        stream.subscribe { |f| }
        expect(stream.filters).to eq({tickers: nil, form_types: nil})
      end

      it "returns normalized uppercase values" do
        stream.subscribe(tickers: ["aapl"], form_types: ["10-k"]) { |f| }
        expect(stream.filters).to eq({tickers: ["AAPL"], form_types: ["10-K"]})
      end
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

  describe "sequential callback processing (Story 6.3, AC: #3)" do
    let(:multi_filing_json) do
      [
        {"accessionNo" => "001", "formType" => "8-K", "filedAt" => "2024-01-15T10:00:00", "cik" => "123", "ticker" => "AAPL", "companyName" => "Apple Inc.", "linkToFilingDetails" => "https://..."},
        {"accessionNo" => "002", "formType" => "10-K", "filedAt" => "2024-01-15T10:01:00", "cik" => "456", "ticker" => "TSLA", "companyName" => "Tesla Inc.", "linkToFilingDetails" => "https://..."},
        {"accessionNo" => "003", "formType" => "10-Q", "filedAt" => "2024-01-15T10:02:00", "cik" => "789", "ticker" => "MSFT", "companyName" => "Microsoft Corp.", "linkToFilingDetails" => "https://..."}
      ].to_json
    end

    before do
      stream.instance_variable_set(:@running, true)
    end

    it "processes filings in order they were received" do
      order = []
      stream.instance_variable_set(:@callback, ->(f) { order << f.accession_no })

      stream.send(:handle_message, multi_filing_json)

      expect(order).to eq(["001", "002", "003"])
    end

    it "invokes callbacks sequentially (not in parallel)" do
      # Track callback start and end to verify sequential execution
      execution_log = []
      stream.instance_variable_set(:@callback, ->(f) {
        execution_log << "start:#{f.accession_no}"
        # Simulate some work
        execution_log << "end:#{f.accession_no}"
      })

      stream.send(:handle_message, multi_filing_json)

      # Sequential execution: start1, end1, start2, end2, start3, end3
      expect(execution_log).to eq([
        "start:001", "end:001",
        "start:002", "end:002",
        "start:003", "end:003"
      ])
    end

    it "maintains order even when some callbacks raise exceptions" do
      order = []
      stream.instance_variable_set(:@callback, ->(f) {
        order << f.accession_no
        raise "Error" if f.accession_no == "002"
      })

      stream.send(:handle_message, multi_filing_json)

      expect(order).to eq(["001", "002", "003"])
    end
  end

  describe "callback exception handling (Story 6.3, AC: #4)" do
    let(:logger) { instance_double(Logger) }
    let(:config_with_logger) do
      instance_double(SecApi::Config,
        api_key: "test_key",
        logger: logger,
        log_level: :error,
        on_callback_error: nil,
        on_filing: nil,
        stream_latency_warning_threshold: 120.0)
    end
    let(:client_with_logger) { instance_double(SecApi::Client, config: config_with_logger) }
    let(:stream_with_logger) { described_class.new(client_with_logger) }

    let(:valid_filing_json) do
      [{"accessionNo" => "001", "formType" => "8-K", "filedAt" => "2024-01-15", "cik" => "123", "ticker" => "AAPL", "companyName" => "Apple Inc.", "linkToFilingDetails" => "https://..."}].to_json
    end

    let(:multi_filing_json) do
      [
        {"accessionNo" => "001", "formType" => "8-K", "filedAt" => "2024-01-15", "cik" => "123", "ticker" => "AAPL", "companyName" => "Apple Inc.", "linkToFilingDetails" => "https://..."},
        {"accessionNo" => "002", "formType" => "10-K", "filedAt" => "2024-01-15", "cik" => "456", "ticker" => "TSLA", "companyName" => "Tesla Inc.", "linkToFilingDetails" => "https://..."},
        {"accessionNo" => "003", "formType" => "10-Q", "filedAt" => "2024-01-15", "cik" => "789", "ticker" => "MSFT", "companyName" => "Microsoft Corp.", "linkToFilingDetails" => "https://..."}
      ].to_json
    end

    describe "exception recovery" do
      before do
        stream.instance_variable_set(:@running, true)
      end

      it "continues processing after callback exception" do
        processed = []
        stream.instance_variable_set(:@callback, ->(f) {
          raise "Test error" if f.ticker == "TSLA"
          processed << f.ticker
        })

        stream.send(:handle_message, multi_filing_json)

        expect(processed).to eq(["AAPL", "MSFT"])
      end

      it "does not crash the stream when callback raises" do
        stream.instance_variable_set(:@callback, ->(f) { raise "Boom!" })

        expect { stream.send(:handle_message, valid_filing_json) }.not_to raise_error
      end

      it "processes all filings even when multiple callbacks raise" do
        processed = []
        stream.instance_variable_set(:@callback, ->(f) {
          processed << f.ticker
          raise "Error for #{f.ticker}"
        })

        stream.send(:handle_message, multi_filing_json)

        expect(processed).to eq(["AAPL", "TSLA", "MSFT"])
      end
    end

    describe "exception logging" do
      before do
        stream_with_logger.instance_variable_set(:@running, true)
        allow(logger).to receive(:info)  # Allow latency logging
        allow(logger).to receive(:warn)  # Allow latency warning
      end

      it "logs callback exception with filing context" do
        stream_with_logger.instance_variable_set(:@callback, ->(f) { raise "Test error" })

        expect(logger).to receive(:error) do |&block|
          log_json = JSON.parse(block.call)
          expect(log_json["event"]).to eq("secapi.stream.callback_error")
          expect(log_json["error_class"]).to eq("RuntimeError")
          expect(log_json["error_message"]).to eq("Test error")
          expect(log_json["accession_no"]).to eq("001")
          expect(log_json["ticker"]).to eq("AAPL")
          expect(log_json["form_type"]).to eq("8-K")
        end

        stream_with_logger.send(:handle_message, valid_filing_json)
      end

      it "does not crash when logger is nil" do
        config_no_logger = instance_double(SecApi::Config,
          api_key: "test_key",
          logger: nil,
          on_callback_error: nil,
          on_filing: nil,
          stream_latency_warning_threshold: 120.0)
        client_no_logger = instance_double(SecApi::Client, config: config_no_logger)
        stream_no_logger = described_class.new(client_no_logger)

        stream_no_logger.instance_variable_set(:@running, true)
        stream_no_logger.instance_variable_set(:@callback, ->(f) { raise "Test error" })

        expect { stream_no_logger.send(:handle_message, valid_filing_json) }.not_to raise_error
      end

      it "does not crash when logger raises exception" do
        stream_with_logger.instance_variable_set(:@callback, ->(f) { raise "Test error" })
        allow(logger).to receive(:error).and_raise("Logger failed!")

        expect { stream_with_logger.send(:handle_message, valid_filing_json) }.not_to raise_error
      end
    end

    describe "on_callback_error callback" do
      it "invokes on_callback_error with error context" do
        error_infos = []
        on_error = ->(info) { error_infos << info }

        config_with_error_cb = instance_double(SecApi::Config,
          api_key: "test_key",
          logger: nil,
          on_callback_error: on_error,
          on_filing: nil,
          stream_latency_warning_threshold: 120.0)
        client_with_error_cb = instance_double(SecApi::Client, config: config_with_error_cb)
        stream_with_error_cb = described_class.new(client_with_error_cb)

        stream_with_error_cb.instance_variable_set(:@running, true)
        stream_with_error_cb.instance_variable_set(:@callback, ->(f) { raise "Callback failed!" })

        stream_with_error_cb.send(:handle_message, valid_filing_json)

        expect(error_infos.size).to eq(1)
        expect(error_infos.first[:error]).to be_a(RuntimeError)
        expect(error_infos.first[:error].message).to eq("Callback failed!")
        expect(error_infos.first[:filing]).to be_a(SecApi::Objects::StreamFiling)
        expect(error_infos.first[:accession_no]).to eq("001")
        expect(error_infos.first[:ticker]).to eq("AAPL")
      end

      it "continues processing when on_callback_error raises" do
        on_error = ->(info) { raise "Error handler failed!" }

        config_with_error_cb = instance_double(SecApi::Config,
          api_key: "test_key",
          logger: nil,
          on_callback_error: on_error,
          on_filing: nil,
          stream_latency_warning_threshold: 120.0)
        client_with_error_cb = instance_double(SecApi::Client, config: config_with_error_cb)
        stream_with_error_cb = described_class.new(client_with_error_cb)

        stream_with_error_cb.instance_variable_set(:@running, true)
        stream_with_error_cb.instance_variable_set(:@callback, ->(f) { raise "Original error" })

        expect { stream_with_error_cb.send(:handle_message, valid_filing_json) }.not_to raise_error
      end

      it "invokes on_callback_error for each failing callback" do
        error_count = 0
        on_error = ->(info) { error_count += 1 }

        config_with_error_cb = instance_double(SecApi::Config,
          api_key: "test_key",
          logger: nil,
          on_callback_error: on_error,
          on_filing: nil,
          stream_latency_warning_threshold: 120.0)
        client_with_error_cb = instance_double(SecApi::Client, config: config_with_error_cb)
        stream_with_error_cb = described_class.new(client_with_error_cb)

        stream_with_error_cb.instance_variable_set(:@running, true)
        stream_with_error_cb.instance_variable_set(:@callback, ->(f) { raise "Error!" })

        stream_with_error_cb.send(:handle_message, multi_filing_json)

        expect(error_count).to eq(3)
      end
    end
  end

  describe "reconnection state tracking (Story 6.4, Task 2)" do
    describe "#initialize" do
      it "initializes @reconnect_attempts to 0" do
        expect(stream.instance_variable_get(:@reconnect_attempts)).to eq(0)
      end

      it "initializes @should_reconnect to true" do
        expect(stream.instance_variable_get(:@should_reconnect)).to be true
      end

      it "initializes @reconnecting to false" do
        expect(stream.instance_variable_get(:@reconnecting)).to be false
      end

      it "initializes @disconnect_time to nil" do
        expect(stream.instance_variable_get(:@disconnect_time)).to be_nil
      end
    end

    describe "state preservation across reconnects" do
      before do
        allow(stream).to receive(:connect)
      end

      it "preserves @tickers across reconnections" do
        stream.subscribe(tickers: ["AAPL", "TSLA"]) { |f| }
        original_tickers = stream.instance_variable_get(:@tickers)

        # Simulate reconnection state
        stream.instance_variable_set(:@reconnecting, true)
        stream.instance_variable_set(:@reconnect_attempts, 1)

        expect(stream.instance_variable_get(:@tickers)).to eq(original_tickers)
      end

      it "preserves @form_types across reconnections" do
        stream.subscribe(form_types: ["10-K", "8-K"]) { |f| }
        original_form_types = stream.instance_variable_get(:@form_types)

        stream.instance_variable_set(:@reconnecting, true)

        expect(stream.instance_variable_get(:@form_types)).to eq(original_form_types)
      end

      it "preserves @callback across reconnections" do
        callback = ->(f) { puts f }
        stream.subscribe(&callback)
        original_callback = stream.instance_variable_get(:@callback)

        stream.instance_variable_set(:@reconnecting, true)

        expect(stream.instance_variable_get(:@callback)).to eq(original_callback)
      end
    end

    describe "@should_reconnect flag" do
      it "starts as true by default" do
        expect(stream.instance_variable_get(:@should_reconnect)).to be true
      end

      it "can be set to false" do
        stream.instance_variable_set(:@should_reconnect, false)
        expect(stream.instance_variable_get(:@should_reconnect)).to be false
      end
    end

    describe "@reconnecting flag" do
      it "starts as false by default" do
        expect(stream.instance_variable_get(:@reconnecting)).to be false
      end

      it "can be set to true during reconnection" do
        stream.instance_variable_set(:@reconnecting, true)
        expect(stream.instance_variable_get(:@reconnecting)).to be true
      end
    end

    describe "@reconnect_attempts counter" do
      it "starts at 0 by default" do
        expect(stream.instance_variable_get(:@reconnect_attempts)).to eq(0)
      end

      it "can be incremented" do
        stream.instance_variable_set(:@reconnect_attempts, 1)
        expect(stream.instance_variable_get(:@reconnect_attempts)).to eq(1)

        stream.instance_variable_set(:@reconnect_attempts, 2)
        expect(stream.instance_variable_get(:@reconnect_attempts)).to eq(2)
      end

      it "can be reset to 0" do
        stream.instance_variable_set(:@reconnect_attempts, 5)
        stream.instance_variable_set(:@reconnect_attempts, 0)
        expect(stream.instance_variable_get(:@reconnect_attempts)).to eq(0)
      end
    end
  end

  describe "#calculate_reconnect_delay (Story 6.4, Task 3)" do
    let(:config) do
      SecApi::Config.new(
        api_key: "test_api_key_valid",
        stream_initial_reconnect_delay: 1.0,
        stream_max_reconnect_delay: 60.0,
        stream_backoff_multiplier: 2
      )
    end
    let(:client) { instance_double(SecApi::Client, config: config) }
    let(:stream) { described_class.new(client) }

    describe "exponential backoff formula" do
      before do
        # Stub rand to return 0.5 (middle of 0-1 range) for predictable jitter
        # Jitter: 0.9 + (0.5 * 0.2) = 1.0 (no jitter effect)
        allow(stream).to receive(:rand).and_return(0.5)
      end

      it "returns initial delay for attempt 0" do
        stream.instance_variable_set(:@reconnect_attempts, 0)
        delay = stream.send(:calculate_reconnect_delay)
        # 1.0 * (2^0) * 1.0 = 1.0
        expect(delay).to eq(1.0)
      end

      it "returns doubled delay for attempt 1" do
        stream.instance_variable_set(:@reconnect_attempts, 1)
        delay = stream.send(:calculate_reconnect_delay)
        # 1.0 * (2^1) * 1.0 = 2.0
        expect(delay).to eq(2.0)
      end

      it "returns quadrupled delay for attempt 2" do
        stream.instance_variable_set(:@reconnect_attempts, 2)
        delay = stream.send(:calculate_reconnect_delay)
        # 1.0 * (2^2) * 1.0 = 4.0
        expect(delay).to eq(4.0)
      end

      it "returns 8x delay for attempt 3" do
        stream.instance_variable_set(:@reconnect_attempts, 3)
        delay = stream.send(:calculate_reconnect_delay)
        # 1.0 * (2^3) * 1.0 = 8.0
        expect(delay).to eq(8.0)
      end
    end

    describe "max delay cap" do
      before do
        allow(stream).to receive(:rand).and_return(0.5)
      end

      it "caps delay at stream_max_reconnect_delay" do
        # Attempt 10: 1.0 * 2^10 = 1024, but max is 60
        stream.instance_variable_set(:@reconnect_attempts, 10)
        delay = stream.send(:calculate_reconnect_delay)
        expect(delay).to eq(60.0)
      end

      it "caps high attempt counts at max delay" do
        stream.instance_variable_set(:@reconnect_attempts, 100)
        delay = stream.send(:calculate_reconnect_delay)
        expect(delay).to eq(60.0)
      end
    end

    describe "jitter" do
      it "adds jitter between 0.9x and 1.1x of delay" do
        stream.instance_variable_set(:@reconnect_attempts, 0)

        # Test with multiple random values
        delays = []
        [0.0, 0.5, 1.0].each do |r|
          allow(stream).to receive(:rand).and_return(r)
          delays << stream.send(:calculate_reconnect_delay)
        end

        # rand=0.0: 1.0 * (0.9 + 0.0*0.2) = 0.9
        # rand=0.5: 1.0 * (0.9 + 0.5*0.2) = 1.0
        # rand=1.0: 1.0 * (0.9 + 1.0*0.2) = 1.1
        expect(delays[0]).to eq(0.9)
        expect(delays[1]).to eq(1.0)
        expect(delays[2]).to eq(1.1)
      end

      it "applies jitter after cap" do
        stream.instance_variable_set(:@reconnect_attempts, 10)

        allow(stream).to receive(:rand).and_return(0.0)
        delay_low = stream.send(:calculate_reconnect_delay)

        allow(stream).to receive(:rand).and_return(1.0)
        delay_high = stream.send(:calculate_reconnect_delay)

        # Jitter on capped 60: 54 to 66
        expect(delay_low).to eq(54.0)
        expect(delay_high).to eq(66.0)
      end

      it "uses actual rand for randomness" do
        stream.instance_variable_set(:@reconnect_attempts, 0)

        # Multiple calls should return slightly different values
        delays = Array.new(10) { stream.send(:calculate_reconnect_delay) }

        # With real randomness, we should not get all identical values
        # (statistically extremely unlikely)
        expect(delays.uniq.size).to be > 1
      end
    end

    describe "return value" do
      it "returns a Float" do
        delay = stream.send(:calculate_reconnect_delay)
        expect(delay).to be_a(Float)
      end
    end

    describe "custom configuration" do
      let(:custom_config) do
        SecApi::Config.new(
          api_key: "test_api_key_valid",
          stream_initial_reconnect_delay: 2.0,
          stream_max_reconnect_delay: 30.0,
          stream_backoff_multiplier: 3
        )
      end
      let(:custom_client) { instance_double(SecApi::Client, config: custom_config) }
      let(:custom_stream) { described_class.new(custom_client) }

      before do
        allow(custom_stream).to receive(:rand).and_return(0.5)
      end

      it "uses custom initial delay" do
        custom_stream.instance_variable_set(:@reconnect_attempts, 0)
        delay = custom_stream.send(:calculate_reconnect_delay)
        expect(delay).to eq(2.0)
      end

      it "uses custom backoff multiplier" do
        custom_stream.instance_variable_set(:@reconnect_attempts, 1)
        delay = custom_stream.send(:calculate_reconnect_delay)
        # 2.0 * (3^1) * 1.0 = 6.0
        expect(delay).to eq(6.0)
      end

      it "uses custom max delay" do
        custom_stream.instance_variable_set(:@reconnect_attempts, 10)
        delay = custom_stream.send(:calculate_reconnect_delay)
        expect(delay).to eq(30.0)
      end
    end
  end

  describe "auto-reconnect on abnormal close (Story 6.4, Task 4)" do
    let(:config) do
      SecApi::Config.new(
        api_key: "test_api_key_valid",
        stream_max_reconnect_attempts: 10,
        stream_initial_reconnect_delay: 1.0,
        stream_max_reconnect_delay: 60.0,
        stream_backoff_multiplier: 2
      )
    end
    let(:client) { instance_double(SecApi::Client, config: config) }
    let(:stream) { described_class.new(client) }

    before do
      allow(EM).to receive(:reactor_running?).and_return(true)
      allow(EM).to receive(:stop_event_loop)
      allow(EM).to receive(:add_timer).and_yield
      allow(stream).to receive(:attempt_reconnect)
    end

    describe "#reconnectable_close?" do
      it "returns true for CLOSE_ABNORMAL (1006)" do
        expect(stream.send(:reconnectable_close?, 1006)).to be true
      end

      it "returns true for server error codes 1011-1015" do
        (1011..1015).each do |code|
          expect(stream.send(:reconnectable_close?, code)).to be true
        end
      end

      it "returns false for CLOSE_NORMAL (1000)" do
        expect(stream.send(:reconnectable_close?, 1000)).to be false
      end

      it "returns false for CLOSE_GOING_AWAY (1001)" do
        expect(stream.send(:reconnectable_close?, 1001)).to be false
      end

      it "returns false for CLOSE_POLICY_VIOLATION (1008)" do
        expect(stream.send(:reconnectable_close?, 1008)).to be false
      end

      it "returns false for other close codes" do
        [1002, 1003, 1007, 1009, 1010].each do |code|
          expect(stream.send(:reconnectable_close?, code)).to be false
        end
      end
    end

    describe "#handle_close with reconnectable codes" do
      before do
        stream.instance_variable_set(:@running, true)
        stream.instance_variable_set(:@should_reconnect, true)
        allow(stream).to receive(:schedule_reconnect)
      end

      it "triggers reconnection for CLOSE_ABNORMAL when should_reconnect is true" do
        expect(stream).to receive(:schedule_reconnect)

        stream.send(:handle_close, 1006, "Abnormal closure")
      end

      it "does NOT trigger reconnection when should_reconnect is false" do
        stream.instance_variable_set(:@should_reconnect, false)
        expect(stream).not_to receive(:schedule_reconnect)

        expect {
          stream.send(:handle_close, 1006, "Abnormal closure")
        }.to raise_error(SecApi::NetworkError)
      end

      it "does NOT trigger reconnection when not previously running" do
        stream.instance_variable_set(:@running, false)
        expect(stream).not_to receive(:schedule_reconnect)

        # Still raises NetworkError since we weren't running when disconnected
        expect {
          stream.send(:handle_close, 1006, "Abnormal closure")
        }.to raise_error(SecApi::NetworkError)
      end

      it "sets disconnect_time when scheduling reconnect" do
        allow(stream).to receive(:schedule_reconnect) do
          # Verify disconnect_time was set before schedule_reconnect called
          expect(stream.instance_variable_get(:@disconnect_time)).not_to be_nil
        end

        stream.send(:handle_close, 1006, "Abnormal closure")
      end
    end

    describe "#handle_close with non-reconnectable codes" do
      before do
        stream.instance_variable_set(:@running, true)
        stream.instance_variable_set(:@should_reconnect, true)
        allow(stream).to receive(:schedule_reconnect)
      end

      it "does NOT reconnect on normal close (1000)" do
        expect(stream).not_to receive(:schedule_reconnect)

        stream.send(:handle_close, 1000, "Normal closure")
      end

      it "does NOT reconnect on policy violation (1008) - raises AuthError instead" do
        expect(stream).not_to receive(:schedule_reconnect)

        expect {
          stream.send(:handle_close, 1008, "Policy violation")
        }.to raise_error(SecApi::AuthenticationError)
      end
    end

    describe "#schedule_reconnect" do
      before do
        stream.instance_variable_set(:@reconnect_attempts, 0)
        allow(stream).to receive(:rand).and_return(0.5)
      end

      it "calls EM.add_timer with calculated delay" do
        expect(EM).to receive(:add_timer).with(1.0)

        stream.send(:schedule_reconnect)
      end

      it "calls attempt_reconnect after delay" do
        expect(stream).to receive(:attempt_reconnect)

        stream.send(:schedule_reconnect)
      end

      it "calls log_reconnect_attempt with calculated delay (AC: #4, Task 5.7)" do
        expect(stream).to receive(:log_reconnect_attempt).with(1.0)

        stream.send(:schedule_reconnect)
      end
    end
  end

  describe "successful reconnection handling (Story 6.4, Task 6)" do
    let(:config) do
      SecApi::Config.new(
        api_key: "test_api_key_valid",
        stream_max_reconnect_attempts: 10
      )
    end
    let(:client) { instance_double(SecApi::Client, config: config) }
    let(:stream) { described_class.new(client) }
    let(:mock_ws) { instance_double(Faye::WebSocket::Client) }

    before do
      allow(mock_ws).to receive(:on).with(:open).and_yield(double("OpenEvent"))
      allow(mock_ws).to receive(:on).with(:message)
      allow(mock_ws).to receive(:on).with(:close)
      allow(mock_ws).to receive(:on).with(:error)
      stream.instance_variable_set(:@ws, mock_ws)
    end

    describe "when reconnection succeeds" do
      before do
        stream.instance_variable_set(:@reconnecting, true)
        stream.instance_variable_set(:@reconnect_attempts, 3)
        stream.instance_variable_set(:@disconnect_time, Time.now - 5)
      end

      it "resets @reconnect_attempts to 0" do
        stream.send(:setup_handlers)
        expect(stream.instance_variable_get(:@reconnect_attempts)).to eq(0)
      end

      it "sets @reconnecting to false" do
        stream.send(:setup_handlers)
        expect(stream.instance_variable_get(:@reconnecting)).to be false
      end

      it "clears @disconnect_time" do
        stream.send(:setup_handlers)
        expect(stream.instance_variable_get(:@disconnect_time)).to be_nil
      end

      it "sets @running to true" do
        stream.send(:setup_handlers)
        expect(stream.instance_variable_get(:@running)).to be true
      end
    end

    describe "when initial connection succeeds (not a reconnection)" do
      before do
        stream.instance_variable_set(:@reconnecting, false)
        stream.instance_variable_set(:@reconnect_attempts, 0)
      end

      it "keeps @reconnect_attempts at 0" do
        stream.send(:setup_handlers)
        expect(stream.instance_variable_get(:@reconnect_attempts)).to eq(0)
      end

      it "sets @running to true" do
        stream.send(:setup_handlers)
        expect(stream.instance_variable_get(:@running)).to be true
      end
    end
  end

  describe "reconnection failure handling (Story 6.4, Task 7)" do
    let(:config) do
      SecApi::Config.new(
        api_key: "test_api_key_valid",
        stream_max_reconnect_attempts: 3
      )
    end
    let(:client) { instance_double(SecApi::Client, config: config) }
    let(:stream) { described_class.new(client) }

    before do
      allow(EM).to receive(:reactor_running?).and_return(true)
      allow(EM).to receive(:stop_event_loop)
    end

    describe "#handle_reconnection_failure" do
      before do
        stream.instance_variable_set(:@reconnect_attempts, 10)
        stream.instance_variable_set(:@disconnect_time, Time.now - 30)
      end

      it "raises ReconnectionError" do
        expect {
          stream.send(:handle_reconnection_failure)
        }.to raise_error(SecApi::ReconnectionError)
      end

      it "includes attempt count in error" do
        expect {
          stream.send(:handle_reconnection_failure)
        }.to raise_error(SecApi::ReconnectionError) do |e|
          expect(e.attempts).to eq(10)
        end
      end

      it "includes downtime in error" do
        expect {
          stream.send(:handle_reconnection_failure)
        }.to raise_error(SecApi::ReconnectionError) do |e|
          expect(e.downtime_seconds).to be_within(1).of(30)
        end
      end

      it "stops EventMachine reactor" do
        expect(EM).to receive(:stop_event_loop)

        begin
          stream.send(:handle_reconnection_failure)
        rescue SecApi::ReconnectionError
          # Expected
        end
      end

      it "sets @running to false" do
        begin
          stream.send(:handle_reconnection_failure)
        rescue SecApi::ReconnectionError
          # Expected
        end

        expect(stream.instance_variable_get(:@running)).to be false
      end

      it "sets @reconnecting to false" do
        stream.instance_variable_set(:@reconnecting, true)

        begin
          stream.send(:handle_reconnection_failure)
        rescue SecApi::ReconnectionError
          # Expected
        end

        expect(stream.instance_variable_get(:@reconnecting)).to be false
      end
    end

    describe "#attempt_reconnect when max exceeded" do
      before do
        stream.instance_variable_set(:@reconnect_attempts, 3)  # At max already
        stream.instance_variable_set(:@disconnect_time, Time.now - 10)
      end

      it "raises ReconnectionError when max attempts exceeded" do
        expect {
          stream.send(:attempt_reconnect)
        }.to raise_error(SecApi::ReconnectionError)
      end

      it "does not create new WebSocket when max exceeded" do
        expect(Faye::WebSocket::Client).not_to receive(:new)

        begin
          stream.send(:attempt_reconnect)
        rescue SecApi::ReconnectionError
          # Expected
        end
      end
    end
  end

  describe "reconnection logging (Story 6.4, Task 8)" do
    # Helper class that captures log messages
    let(:log_capture_class) do
      Class.new do
        attr_reader :messages

        def initialize
          @messages = []
        end

        def info(&block)
          @messages << block.call if block
        end
      end
    end

    describe "#log_reconnect_attempt" do
      let(:logger) { log_capture_class.new }
      let(:config) do
        SecApi::Config.new(
          api_key: "test_api_key_valid",
          stream_max_reconnect_attempts: 10,
          logger: logger,
          log_level: :info
        )
      end
      let(:client) { instance_double(SecApi::Client, config: config) }
      let(:stream) { described_class.new(client) }

      before do
        stream.instance_variable_set(:@reconnect_attempts, 2)
        stream.instance_variable_set(:@disconnect_time, Time.now - 5)
        allow(stream).to receive(:rand).and_return(0.5)
      end

      it "logs reconnection attempt with JSON format" do
        stream.send(:log_reconnect_attempt, 4.0)

        expect(logger.messages).not_to be_empty
        log_json = JSON.parse(logger.messages.first)
        expect(log_json["event"]).to eq("secapi.stream.reconnect_attempt")
        expect(log_json["attempt"]).to eq(2)
        expect(log_json["max_attempts"]).to eq(10)
        expect(log_json["delay"]).to be_a(Numeric)
      end

      it "includes elapsed time since disconnect" do
        stream.send(:log_reconnect_attempt, 4.0)

        log_json = JSON.parse(logger.messages.first)
        expect(log_json["elapsed_seconds"]).to be_within(1).of(5)
      end

      it "does not fail when logger is nil" do
        config_no_logger = SecApi::Config.new(api_key: "test_api_key_valid")
        client_no_logger = instance_double(SecApi::Client, config: config_no_logger)
        stream_no_logger = described_class.new(client_no_logger)

        expect { stream_no_logger.send(:log_reconnect_attempt, 1.0) }.not_to raise_error
      end
    end

    describe "#log_reconnect_success" do
      let(:logger) { log_capture_class.new }
      let(:config) do
        SecApi::Config.new(
          api_key: "test_api_key_valid",
          stream_max_reconnect_attempts: 10,
          logger: logger,
          log_level: :info
        )
      end
      let(:client) { instance_double(SecApi::Client, config: config) }
      let(:stream) { described_class.new(client) }
      let(:mock_ws) { instance_double(Faye::WebSocket::Client) }

      before do
        stream.instance_variable_set(:@reconnect_attempts, 3)
        stream.instance_variable_set(:@disconnect_time, Time.now - 10)
        stream.instance_variable_set(:@reconnecting, true)
        stream.instance_variable_set(:@ws, mock_ws)

        allow(mock_ws).to receive(:on).with(:open).and_yield(double("OpenEvent"))
        allow(mock_ws).to receive(:on).with(:message)
        allow(mock_ws).to receive(:on).with(:close)
        allow(mock_ws).to receive(:on).with(:error)
      end

      it "logs successful reconnection with JSON format" do
        stream.send(:setup_handlers)

        expect(logger.messages).not_to be_empty
        log_json = JSON.parse(logger.messages.first)
        expect(log_json["event"]).to eq("secapi.stream.reconnect_success")
        expect(log_json["attempts"]).to eq(3)
        expect(log_json["downtime_seconds"]).to be_within(1).of(10)
      end

      it "does not log when not reconnecting" do
        stream.instance_variable_set(:@reconnecting, false)

        stream.send(:setup_handlers)

        expect(logger.messages).to be_empty
      end

      it "does not fail when logger is nil" do
        config_no_logger = SecApi::Config.new(api_key: "test_api_key_valid")
        client_no_logger = instance_double(SecApi::Client, config: config_no_logger)
        stream_no_logger = described_class.new(client_no_logger)
        stream_no_logger.instance_variable_set(:@reconnecting, true)
        stream_no_logger.instance_variable_set(:@ws, mock_ws)

        expect { stream_no_logger.send(:setup_handlers) }.not_to raise_error
      end
    end
  end

  describe "latency instrumentation (Story 6.5)" do
    # Use a real logger-like object that captures messages
    let(:log_capture_class) do
      Class.new do
        attr_reader :info_messages, :warn_messages

        def initialize
          @info_messages = []
          @warn_messages = []
        end

        def info(&block)
          @info_messages << block.call if block
        end

        def warn(&block)
          @warn_messages << block.call if block
        end
      end
    end
    let(:logger) { log_capture_class.new }
    let(:on_filing_calls) { [] }
    let(:on_filing_callback) { ->(filing:, latency_ms:, received_at:) { on_filing_calls << {filing: filing, latency_ms: latency_ms, received_at: received_at} } }
    let(:latency_config) do
      SecApi::Config.new(
        api_key: "test_api_key_valid",
        logger: logger,
        log_level: :info,
        on_filing: on_filing_callback,
        stream_latency_warning_threshold: 120.0
      )
    end
    let(:latency_client) { instance_double(SecApi::Client, config: latency_config) }
    let(:latency_stream) { described_class.new(latency_client) }

    let(:filing_json) do
      [{
        "accessionNo" => "0001193125-24-123456",
        "formType" => "8-K",
        "filedAt" => (Time.now - 60).iso8601(3),  # 60 seconds ago
        "cik" => "320193",
        "ticker" => "AAPL",
        "companyName" => "Apple Inc.",
        "linkToFilingDetails" => "https://sec-api.io/filing/..."
      }].to_json
    end

    let(:old_filing_json) do
      [{
        "accessionNo" => "0001193125-24-999999",
        "formType" => "10-K",
        "filedAt" => (Time.now - 180).iso8601(3),  # 180 seconds ago (over threshold)
        "cik" => "320193",
        "ticker" => "TSLA",
        "companyName" => "Tesla Inc.",
        "linkToFilingDetails" => "https://sec-api.io/filing/..."
      }].to_json
    end

    before do
      latency_stream.instance_variable_set(:@running, true)
      latency_stream.instance_variable_set(:@callback, ->(f) {})
    end

    describe "received_at timestamp capture (Task 5)" do
      it "captures received_at timestamp on StreamFiling" do
        received_filing = nil
        latency_stream.instance_variable_set(:@callback, ->(f) { received_filing = f })

        latency_stream.send(:handle_message, filing_json)

        expect(received_filing.received_at).to be_a(Time)
        expect(received_filing.received_at).to be_within(1).of(Time.now)
      end

      it "captures timestamp before processing" do
        before_time = Time.now
        received_filing = nil
        latency_stream.instance_variable_set(:@callback, ->(f) { received_filing = f })

        latency_stream.send(:handle_message, filing_json)

        expect(received_filing.received_at).to be >= before_time
      end
    end

    describe "on_filing callback invocation (Task 6)" do
      it "invokes on_filing callback for each filing" do
        latency_stream.send(:handle_message, filing_json)

        expect(on_filing_calls.size).to eq(1)
      end

      it "passes filing object to callback" do
        latency_stream.send(:handle_message, filing_json)

        expect(on_filing_calls.first[:filing]).to be_a(SecApi::Objects::StreamFiling)
        expect(on_filing_calls.first[:filing].accession_no).to eq("0001193125-24-123456")
      end

      it "passes latency_ms to callback" do
        latency_stream.send(:handle_message, filing_json)

        expect(on_filing_calls.first[:latency_ms]).to be_a(Integer)
        expect(on_filing_calls.first[:latency_ms]).to be_within(5000).of(60000)  # ~60 seconds
      end

      it "passes received_at to callback" do
        latency_stream.send(:handle_message, filing_json)

        expect(on_filing_calls.first[:received_at]).to be_a(Time)
      end

      it "continues processing when on_filing callback raises" do
        error_config = SecApi::Config.new(
          api_key: "test_api_key_valid",
          on_filing: ->(filing:, latency_ms:, received_at:) { raise "Callback error!" }
        )
        error_client = instance_double(SecApi::Client, config: error_config)
        error_stream = described_class.new(error_client)
        error_stream.instance_variable_set(:@running, true)

        received = []
        error_stream.instance_variable_set(:@callback, ->(f) { received << f })

        expect { error_stream.send(:handle_message, filing_json) }.not_to raise_error
        expect(received.size).to eq(1)
      end

      it "invokes on_filing before user callback" do
        call_order = []
        on_filing_tracking = ->(filing:, latency_ms:, received_at:) { call_order << :on_filing }
        user_callback = ->(f) { call_order << :user_callback }

        tracking_config = SecApi::Config.new(
          api_key: "test_api_key_valid",
          on_filing: on_filing_tracking
        )
        tracking_client = instance_double(SecApi::Client, config: tracking_config)
        tracking_stream = described_class.new(tracking_client)
        tracking_stream.instance_variable_set(:@running, true)
        tracking_stream.instance_variable_set(:@callback, user_callback)

        tracking_stream.send(:handle_message, filing_json)

        expect(call_order).to eq([:on_filing, :user_callback])
      end

      it "does not invoke on_filing when callback is nil" do
        nil_config = SecApi::Config.new(api_key: "test_api_key_valid")
        nil_client = instance_double(SecApi::Client, config: nil_config)
        nil_stream = described_class.new(nil_client)
        nil_stream.instance_variable_set(:@running, true)
        nil_stream.instance_variable_set(:@callback, ->(f) {})

        expect { nil_stream.send(:handle_message, filing_json) }.not_to raise_error
      end
    end

    describe "latency logging (Task 7)" do
      it "logs filing receipt with latency data" do
        latency_stream.send(:handle_message, filing_json)

        expect(logger.info_messages).not_to be_empty
        log_json = JSON.parse(logger.info_messages.first)
        expect(log_json["event"]).to eq("secapi.stream.filing_received")
        expect(log_json["accession_no"]).to eq("0001193125-24-123456")
        expect(log_json["ticker"]).to eq("AAPL")
        expect(log_json["form_type"]).to eq("8-K")
        expect(log_json["latency_ms"]).to be_a(Integer)
        expect(log_json["received_at"]).not_to be_nil
      end

      it "does not fail when logger is nil" do
        nil_config = SecApi::Config.new(api_key: "test_api_key_valid")
        nil_client = instance_double(SecApi::Client, config: nil_config)
        nil_stream = described_class.new(nil_client)
        nil_stream.instance_variable_set(:@running, true)
        nil_stream.instance_variable_set(:@callback, ->(f) {})

        expect { nil_stream.send(:handle_message, filing_json) }.not_to raise_error
      end
    end

    describe "latency threshold warning (Task 8)" do
      it "logs warning when latency exceeds threshold" do
        latency_stream.send(:handle_message, old_filing_json)

        expect(logger.warn_messages).not_to be_empty
        log_json = JSON.parse(logger.warn_messages.first)
        expect(log_json["event"]).to eq("secapi.stream.latency_warning")
        expect(log_json["latency_ms"]).to be_a(Integer)
        expect(log_json["threshold_seconds"]).to eq(120.0)
      end

      it "does not log warning when latency is under threshold" do
        latency_stream.send(:handle_message, filing_json)

        expect(logger.warn_messages).to be_empty
      end

      it "includes filing metadata in warning" do
        latency_stream.send(:handle_message, old_filing_json)

        expect(logger.warn_messages).not_to be_empty
        log_json = JSON.parse(logger.warn_messages.first)
        expect(log_json["accession_no"]).to eq("0001193125-24-999999")
        expect(log_json["ticker"]).to eq("TSLA")
        expect(log_json["form_type"]).to eq("10-K")
      end
    end
  end

  describe "on_reconnect callback (Story 6.4, Task 10)" do
    let(:reconnect_calls) { [] }
    let(:on_reconnect_callback) { ->(info) { reconnect_calls << info } }
    let(:config) do
      SecApi::Config.new(
        api_key: "test_api_key_valid",
        on_reconnect: on_reconnect_callback
      )
    end
    let(:client) { instance_double(SecApi::Client, config: config) }
    let(:stream) { described_class.new(client) }
    let(:mock_ws) { instance_double(Faye::WebSocket::Client) }

    before do
      stream.instance_variable_set(:@reconnecting, true)
      stream.instance_variable_set(:@reconnect_attempts, 3)
      stream.instance_variable_set(:@disconnect_time, Time.now - 15.5)
      stream.instance_variable_set(:@ws, mock_ws)

      allow(mock_ws).to receive(:on).with(:open).and_yield(double("OpenEvent"))
      allow(mock_ws).to receive(:on).with(:message)
      allow(mock_ws).to receive(:on).with(:close)
      allow(mock_ws).to receive(:on).with(:error)
    end

    it "invokes on_reconnect callback when reconnection succeeds" do
      stream.send(:setup_handlers)

      expect(reconnect_calls.size).to eq(1)
    end

    it "passes attempt_count to callback" do
      stream.send(:setup_handlers)

      expect(reconnect_calls.first[:attempt_count]).to eq(3)
    end

    it "passes downtime_seconds to callback" do
      stream.send(:setup_handlers)

      expect(reconnect_calls.first[:downtime_seconds]).to be_within(1).of(15.5)
    end

    it "does not invoke callback when not reconnecting" do
      stream.instance_variable_set(:@reconnecting, false)

      stream.send(:setup_handlers)

      expect(reconnect_calls).to be_empty
    end

    it "continues if callback raises exception" do
      error_config = SecApi::Config.new(
        api_key: "test_api_key_valid",
        on_reconnect: ->(info) { raise "Callback error!" }
      )
      error_client = instance_double(SecApi::Client, config: error_config)
      error_stream = described_class.new(error_client)
      error_stream.instance_variable_set(:@reconnecting, true)
      error_stream.instance_variable_set(:@reconnect_attempts, 2)
      error_stream.instance_variable_set(:@ws, mock_ws)

      expect { error_stream.send(:setup_handlers) }.not_to raise_error
      expect(error_stream.instance_variable_get(:@running)).to be true
    end

    it "does not invoke callback when on_reconnect is nil" do
      nil_config = SecApi::Config.new(api_key: "test_api_key_valid")
      nil_client = instance_double(SecApi::Client, config: nil_config)
      nil_stream = described_class.new(nil_client)
      nil_stream.instance_variable_set(:@reconnecting, true)
      nil_stream.instance_variable_set(:@reconnect_attempts, 1)
      nil_stream.instance_variable_set(:@ws, mock_ws)

      expect { nil_stream.send(:setup_handlers) }.not_to raise_error
    end
  end
end
