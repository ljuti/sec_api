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
        on_callback_error: nil)
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
          on_callback_error: nil)
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
          on_callback_error: on_error)
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
          on_callback_error: on_error)
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
          on_callback_error: on_error)
        client_with_error_cb = instance_double(SecApi::Client, config: config_with_error_cb)
        stream_with_error_cb = described_class.new(client_with_error_cb)

        stream_with_error_cb.instance_variable_set(:@running, true)
        stream_with_error_cb.instance_variable_set(:@callback, ->(f) { raise "Error!" })

        stream_with_error_cb.send(:handle_message, multi_filing_json)

        expect(error_count).to eq(3)
      end
    end
  end
end
