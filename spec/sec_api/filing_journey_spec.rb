# frozen_string_literal: true

RSpec.describe SecApi::FilingJourney do
  let(:logger) { instance_double(Logger) }
  let(:accession_no) { "0000320193-24-000001" }

  describe ".log_detected" do
    it "logs filing detection with required fields" do
      expect(logger).to receive(:info) do |&block|
        json = JSON.parse(block.call)
        expect(json["event"]).to eq("secapi.filing.journey.detected")
        expect(json["stage"]).to eq("detected")
        expect(json["accession_no"]).to eq(accession_no)
        expect(json).to have_key("timestamp")
      end

      described_class.log_detected(logger, :info, accession_no: accession_no)
    end

    it "includes optional ticker and form_type" do
      expect(logger).to receive(:info) do |&block|
        json = JSON.parse(block.call)
        expect(json["ticker"]).to eq("AAPL")
        expect(json["form_type"]).to eq("10-K")
      end

      described_class.log_detected(logger, :info,
        accession_no: accession_no,
        ticker: "AAPL",
        form_type: "10-K")
    end

    it "includes optional latency_ms" do
      expect(logger).to receive(:info) do |&block|
        json = JSON.parse(block.call)
        expect(json["latency_ms"]).to eq(500)
      end

      described_class.log_detected(logger, :info,
        accession_no: accession_no,
        latency_ms: 500)
    end

    it "excludes nil optional fields" do
      expect(logger).to receive(:info) do |&block|
        json = JSON.parse(block.call)
        expect(json).not_to have_key("ticker")
        expect(json).not_to have_key("form_type")
        expect(json).not_to have_key("latency_ms")
      end

      described_class.log_detected(logger, :info, accession_no: accession_no)
    end
  end

  describe ".log_queried" do
    it "logs query completion with required fields" do
      expect(logger).to receive(:info) do |&block|
        json = JSON.parse(block.call)
        expect(json["event"]).to eq("secapi.filing.journey.queried")
        expect(json["stage"]).to eq("queried")
        expect(json["accession_no"]).to eq(accession_no)
        expect(json).to have_key("timestamp")
      end

      described_class.log_queried(logger, :info, accession_no: accession_no)
    end

    it "includes optional found, request_id, and duration_ms" do
      expect(logger).to receive(:info) do |&block|
        json = JSON.parse(block.call)
        expect(json["found"]).to be true
        expect(json["request_id"]).to eq("req-123")
        expect(json["duration_ms"]).to eq(150)
      end

      described_class.log_queried(logger, :info,
        accession_no: accession_no,
        found: true,
        request_id: "req-123",
        duration_ms: 150)
    end
  end

  describe ".log_extracted" do
    it "logs extraction completion with required fields" do
      expect(logger).to receive(:info) do |&block|
        json = JSON.parse(block.call)
        expect(json["event"]).to eq("secapi.filing.journey.extracted")
        expect(json["stage"]).to eq("extracted")
        expect(json["accession_no"]).to eq(accession_no)
        expect(json).to have_key("timestamp")
      end

      described_class.log_extracted(logger, :info, accession_no: accession_no)
    end

    it "includes optional facts_count, request_id, and duration_ms" do
      expect(logger).to receive(:info) do |&block|
        json = JSON.parse(block.call)
        expect(json["facts_count"]).to eq(42)
        expect(json["request_id"]).to eq("req-456")
        expect(json["duration_ms"]).to eq(200)
      end

      described_class.log_extracted(logger, :info,
        accession_no: accession_no,
        facts_count: 42,
        request_id: "req-456",
        duration_ms: 200)
    end
  end

  describe ".log_processed" do
    it "logs processing completion with required fields" do
      expect(logger).to receive(:info) do |&block|
        json = JSON.parse(block.call)
        expect(json["event"]).to eq("secapi.filing.journey.processed")
        expect(json["stage"]).to eq("processed")
        expect(json["accession_no"]).to eq(accession_no)
        expect(json).to have_key("timestamp")
      end

      described_class.log_processed(logger, :info, accession_no: accession_no)
    end

    it "includes success=true by default" do
      expect(logger).to receive(:info) do |&block|
        json = JSON.parse(block.call)
        expect(json["success"]).to be true
      end

      described_class.log_processed(logger, :info, accession_no: accession_no)
    end

    it "includes optional total_duration_ms and error_class on failure" do
      expect(logger).to receive(:error) do |&block|
        json = JSON.parse(block.call)
        expect(json["success"]).to be false
        expect(json["total_duration_ms"]).to eq(5000)
        expect(json["error_class"]).to eq("RuntimeError")
      end

      described_class.log_processed(logger, :error,
        accession_no: accession_no,
        success: false,
        total_duration_ms: 5000,
        error_class: "RuntimeError")
    end
  end

  describe ".calculate_duration_ms" do
    it "calculates duration between two timestamps in milliseconds" do
      start_time = Time.now
      end_time = start_time + 1.5 # 1.5 seconds

      result = described_class.calculate_duration_ms(start_time, end_time)
      expect(result).to eq(1500)
    end

    it "uses current time as default end_time" do
      start_time = Time.now - 0.5 # 500ms ago

      result = described_class.calculate_duration_ms(start_time)
      expect(result).to be >= 500
      expect(result).to be < 600
    end

    it "returns integer milliseconds" do
      start_time = Time.now
      end_time = start_time + 0.1234 # 123.4ms

      result = described_class.calculate_duration_ms(start_time, end_time)
      expect(result).to be_a(Integer)
      expect(result).to eq(123)
    end
  end

  describe "error handling" do
    it "does not raise when logger is nil" do
      expect {
        described_class.log_detected(nil, :info, accession_no: accession_no)
      }.not_to raise_error
    end

    it "does not raise when logger raises an error" do
      allow(logger).to receive(:info).and_raise(StandardError.new("Logger broken"))

      expect {
        described_class.log_detected(logger, :info, accession_no: accession_no)
      }.not_to raise_error
    end
  end

  describe "stage constants" do
    it "defines STAGE_DETECTED" do
      expect(described_class::STAGE_DETECTED).to eq("detected")
    end

    it "defines STAGE_QUERIED" do
      expect(described_class::STAGE_QUERIED).to eq("queried")
    end

    it "defines STAGE_EXTRACTED" do
      expect(described_class::STAGE_EXTRACTED).to eq("extracted")
    end

    it "defines STAGE_PROCESSED" do
      expect(described_class::STAGE_PROCESSED).to eq("processed")
    end
  end

  describe "timestamp format" do
    it "uses ISO8601 format with milliseconds" do
      expect(logger).to receive(:info) do |&block|
        json = JSON.parse(block.call)
        timestamp = json["timestamp"]
        # ISO8601 with milliseconds: 2024-01-15T10:30:00.123Z
        expect(timestamp).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z/)
      end

      described_class.log_detected(logger, :info, accession_no: accession_no)
    end
  end

  describe "log levels" do
    it "respects different log levels" do
      %i[debug info warn error].each do |level|
        expect(logger).to receive(level) do |&block|
          json = JSON.parse(block.call)
          expect(json["accession_no"]).to eq(accession_no)
        end

        described_class.log_detected(logger, level, accession_no: accession_no)
      end
    end
  end

  describe "integration: complete pipeline journey" do
    let(:captured_logs) { [] }
    let(:real_logger) do
      l = Logger.new(StringIO.new)
      allow(l).to receive(:info) do |&block|
        captured_logs << JSON.parse(block.call)
      end
      l
    end
    let(:metrics_backend) { instance_double("StatsD") }

    before do
      allow(metrics_backend).to receive(:histogram)
      allow(metrics_backend).to receive(:method).with(:histogram).and_return(double(arity: -1))
    end

    it "logs complete pipeline with accession_no correlation" do
      # Stage 1: Detection
      described_class.log_detected(real_logger, :info,
        accession_no: accession_no,
        ticker: "AAPL",
        form_type: "10-K")

      # Stage 2: Query
      described_class.log_queried(real_logger, :info,
        accession_no: accession_no,
        found: true,
        duration_ms: 150)

      # Stage 3: Extraction
      described_class.log_extracted(real_logger, :info,
        accession_no: accession_no,
        facts_count: 42,
        duration_ms: 200)

      # Stage 4: Processing
      described_class.log_processed(real_logger, :info,
        accession_no: accession_no,
        success: true,
        total_duration_ms: 500)

      # Verify all stages were logged
      expect(captured_logs.size).to eq(4)

      # Verify accession_no correlation across all stages
      captured_logs.each do |log|
        expect(log["accession_no"]).to eq(accession_no)
      end

      # Verify stage sequence
      stages = captured_logs.map { |log| log["stage"] }
      expect(stages).to eq(%w[detected queried extracted processed])

      # Verify event naming convention
      events = captured_logs.map { |log| log["event"] }
      expect(events).to eq([
        "secapi.filing.journey.detected",
        "secapi.filing.journey.queried",
        "secapi.filing.journey.extracted",
        "secapi.filing.journey.processed"
      ])
    end

    it "preserves timestamp ordering across stages" do
      # Log all stages with small delays
      described_class.log_detected(real_logger, :info, accession_no: accession_no)
      sleep(0.001) # 1ms
      described_class.log_queried(real_logger, :info, accession_no: accession_no)
      sleep(0.001)
      described_class.log_extracted(real_logger, :info, accession_no: accession_no)
      sleep(0.001)
      described_class.log_processed(real_logger, :info, accession_no: accession_no)

      # Parse timestamps and verify ordering
      timestamps = captured_logs.map { |log| Time.iso8601(log["timestamp"]) }

      timestamps.each_cons(2) do |earlier, later|
        expect(later).to be >= earlier
      end
    end

    it "integrates with MetricsCollector for journey metrics" do
      # Record stage metrics
      expect(metrics_backend).to receive(:histogram).with(
        "sec_api.filing.journey.stage_ms", 150, tags: ["stage:queried", "form_type:10-K"]
      )
      expect(metrics_backend).to receive(:histogram).with(
        "sec_api.filing.journey.stage_ms", 200, tags: ["stage:extracted", "form_type:10-K"]
      )
      expect(metrics_backend).to receive(:histogram).with(
        "sec_api.filing.journey.total_ms", 500, tags: ["success:true", "form_type:10-K"]
      )

      # Simulate pipeline with metrics
      SecApi::MetricsCollector.record_journey_stage(metrics_backend,
        stage: "queried", duration_ms: 150, form_type: "10-K")

      SecApi::MetricsCollector.record_journey_stage(metrics_backend,
        stage: "extracted", duration_ms: 200, form_type: "10-K")

      SecApi::MetricsCollector.record_journey_total(metrics_backend,
        total_ms: 500, form_type: "10-K", success: true)
    end

    it "handles failed pipeline with error tracking" do
      # Log detection and processing failure
      described_class.log_detected(real_logger, :info,
        accession_no: accession_no,
        ticker: "AAPL",
        form_type: "10-K")

      allow(real_logger).to receive(:error) do |&block|
        captured_logs << JSON.parse(block.call)
      end

      described_class.log_processed(real_logger, :error,
        accession_no: accession_no,
        success: false,
        total_duration_ms: 100,
        error_class: "SecApi::ValidationError")

      # Find the processed log
      processed_log = captured_logs.find { |log| log["stage"] == "processed" }

      expect(processed_log["success"]).to be false
      expect(processed_log["error_class"]).to eq("SecApi::ValidationError")
      expect(processed_log["total_duration_ms"]).to eq(100)
    end

    it "supports partial pipeline (skipped stages)" do
      # Some filings skip extraction (non-XBRL forms like 8-K)
      described_class.log_detected(real_logger, :info,
        accession_no: accession_no,
        ticker: "AAPL",
        form_type: "8-K")

      # Skip query and extraction, go straight to processing
      described_class.log_processed(real_logger, :info,
        accession_no: accession_no,
        success: true,
        total_duration_ms: 50)

      expect(captured_logs.size).to eq(2)
      stages = captured_logs.map { |log| log["stage"] }
      expect(stages).to eq(%w[detected processed])
    end
  end
end
