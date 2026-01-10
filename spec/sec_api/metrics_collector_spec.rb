# frozen_string_literal: true

RSpec.describe SecApi::MetricsCollector do
  let(:backend) { instance_double("StatsD") }

  before do
    allow(backend).to receive(:increment)
    allow(backend).to receive(:histogram)
    allow(backend).to receive(:gauge)
    # Simulate dogstatsd-ruby interface (supports tags)
    allow(backend).to receive(:method).with(:increment).and_return(double(arity: -1))
    allow(backend).to receive(:method).with(:histogram).and_return(double(arity: -1))
    allow(backend).to receive(:method).with(:gauge).and_return(double(arity: -1))
  end

  describe "metric name constants" do
    it "defines standard request metrics" do
      expect(described_class::REQUESTS_TOTAL).to eq("sec_api.requests.total")
      expect(described_class::REQUESTS_SUCCESS).to eq("sec_api.requests.success")
      expect(described_class::REQUESTS_ERROR).to eq("sec_api.requests.error")
      expect(described_class::REQUESTS_DURATION).to eq("sec_api.requests.duration_ms")
    end

    it "defines standard retry metrics" do
      expect(described_class::RETRIES_TOTAL).to eq("sec_api.retries.total")
      expect(described_class::RETRIES_EXHAUSTED).to eq("sec_api.retries.exhausted")
    end

    it "defines standard rate limit metrics" do
      expect(described_class::RATE_LIMIT_HIT).to eq("sec_api.rate_limit.hit")
      expect(described_class::RATE_LIMIT_THROTTLE).to eq("sec_api.rate_limit.throttle")
    end

    it "defines standard stream metrics" do
      expect(described_class::STREAM_FILINGS).to eq("sec_api.stream.filings")
      expect(described_class::STREAM_LATENCY).to eq("sec_api.stream.latency_ms")
      expect(described_class::STREAM_RECONNECTS).to eq("sec_api.stream.reconnects")
    end

    it "defines standard journey metrics" do
      expect(described_class::JOURNEY_STAGE_DURATION).to eq("sec_api.filing.journey.stage_ms")
      expect(described_class::JOURNEY_TOTAL_DURATION).to eq("sec_api.filing.journey.total_ms")
    end
  end

  describe ".record_response" do
    context "with successful response (2xx)" do
      it "increments total and success counters" do
        expect(backend).to receive(:increment).with("sec_api.requests.total", tags: ["method:GET", "status:200"])
        expect(backend).to receive(:increment).with("sec_api.requests.success", tags: ["method:GET", "status:200"])

        described_class.record_response(backend, status: 200, duration_ms: 150, method: :get)
      end

      it "records duration histogram" do
        expect(backend).to receive(:histogram).with("sec_api.requests.duration_ms", 150, tags: ["method:GET", "status:200"])

        described_class.record_response(backend, status: 200, duration_ms: 150, method: :get)
      end
    end

    context "with client error response (4xx)" do
      it "increments total and error counters" do
        expect(backend).to receive(:increment).with("sec_api.requests.total", tags: ["method:POST", "status:404"])
        expect(backend).to receive(:increment).with("sec_api.requests.error", tags: ["method:POST", "status:404"])

        described_class.record_response(backend, status: 404, duration_ms: 50, method: :post)
      end
    end

    context "with server error response (5xx)" do
      it "increments total and error counters" do
        expect(backend).to receive(:increment).with("sec_api.requests.total", tags: ["method:GET", "status:500"])
        expect(backend).to receive(:increment).with("sec_api.requests.error", tags: ["method:GET", "status:500"])

        described_class.record_response(backend, status: 500, duration_ms: 1000, method: :get)
      end
    end

    context "with nil backend" do
      it "does not raise an error" do
        expect { described_class.record_response(nil, status: 200, duration_ms: 150, method: :get) }.not_to raise_error
      end
    end
  end

  describe ".record_retry" do
    it "increments retry counter with attempt and error_class tags" do
      expect(backend).to receive(:increment).with("sec_api.retries.total", tags: ["attempt:1", "error_class:SecApi::NetworkError"])

      described_class.record_retry(backend, attempt: 1, error_class: "SecApi::NetworkError")
    end

    it "handles multiple attempts" do
      expect(backend).to receive(:increment).with("sec_api.retries.total", tags: ["attempt:3", "error_class:SecApi::ServerError"])

      described_class.record_retry(backend, attempt: 3, error_class: "SecApi::ServerError")
    end

    context "with nil backend" do
      it "does not raise an error" do
        expect { described_class.record_retry(nil, attempt: 1, error_class: "SecApi::NetworkError") }.not_to raise_error
      end
    end
  end

  describe ".record_error" do
    it "increments exhausted counter with error_class and method tags" do
      expect(backend).to receive(:increment).with("sec_api.retries.exhausted", tags: ["error_class:SecApi::NetworkError", "method:GET"])

      described_class.record_error(backend, error_class: "SecApi::NetworkError", method: :get)
    end

    context "with nil backend" do
      it "does not raise an error" do
        expect { described_class.record_error(nil, error_class: "SecApi::NetworkError", method: :get) }.not_to raise_error
      end
    end
  end

  describe ".record_rate_limit" do
    it "increments rate limit hit counter" do
      expect(backend).to receive(:increment).with("sec_api.rate_limit.hit")

      described_class.record_rate_limit(backend)
    end

    it "records retry_after gauge when provided" do
      expect(backend).to receive(:increment).with("sec_api.rate_limit.hit")
      expect(backend).to receive(:gauge).with("sec_api.rate_limit.retry_after", 30)

      described_class.record_rate_limit(backend, retry_after: 30)
    end

    it "does not record gauge when retry_after is nil" do
      expect(backend).to receive(:increment).with("sec_api.rate_limit.hit")
      expect(backend).not_to receive(:gauge)

      described_class.record_rate_limit(backend, retry_after: nil)
    end

    context "with nil backend" do
      it "does not raise an error" do
        expect { described_class.record_rate_limit(nil) }.not_to raise_error
      end
    end
  end

  describe ".record_throttle" do
    it "increments throttle counter" do
      expect(backend).to receive(:increment).with("sec_api.rate_limit.throttle")

      described_class.record_throttle(backend, remaining: 5, delay: 1.5)
    end

    it "records remaining gauge" do
      expect(backend).to receive(:gauge).with("sec_api.rate_limit.remaining", 5)

      described_class.record_throttle(backend, remaining: 5, delay: 1.5)
    end

    it "records delay histogram in milliseconds" do
      expect(backend).to receive(:histogram).with("sec_api.rate_limit.delay_ms", 1500)

      described_class.record_throttle(backend, remaining: 5, delay: 1.5)
    end

    context "with nil backend" do
      it "does not raise an error" do
        expect { described_class.record_throttle(nil, remaining: 5, delay: 1.5) }.not_to raise_error
      end
    end
  end

  describe ".record_filing" do
    it "increments filing counter with form_type tag" do
      expect(backend).to receive(:increment).with("sec_api.stream.filings", tags: ["form_type:10-K"])

      described_class.record_filing(backend, latency_ms: 500, form_type: "10-K")
    end

    it "records latency histogram with form_type tag" do
      expect(backend).to receive(:histogram).with("sec_api.stream.latency_ms", 500, tags: ["form_type:10-K"])

      described_class.record_filing(backend, latency_ms: 500, form_type: "10-K")
    end

    context "with nil backend" do
      it "does not raise an error" do
        expect { described_class.record_filing(nil, latency_ms: 500, form_type: "10-K") }.not_to raise_error
      end
    end
  end

  describe ".record_reconnect" do
    it "increments reconnect counter" do
      expect(backend).to receive(:increment).with("sec_api.stream.reconnects")

      described_class.record_reconnect(backend, attempt_count: 3, downtime_seconds: 15.5)
    end

    it "records reconnect attempts gauge" do
      expect(backend).to receive(:gauge).with("sec_api.stream.reconnect_attempts", 3)

      described_class.record_reconnect(backend, attempt_count: 3, downtime_seconds: 15.5)
    end

    it "records downtime histogram in milliseconds" do
      expect(backend).to receive(:histogram).with("sec_api.stream.downtime_ms", 15500)

      described_class.record_reconnect(backend, attempt_count: 3, downtime_seconds: 15.5)
    end

    context "with nil backend" do
      it "does not raise an error" do
        expect { described_class.record_reconnect(nil, attempt_count: 3, downtime_seconds: 15.5) }.not_to raise_error
      end
    end
  end

  describe ".record_journey_stage" do
    it "records stage duration histogram with stage tag" do
      expect(backend).to receive(:histogram).with("sec_api.filing.journey.stage_ms", 150, tags: ["stage:queried"])

      described_class.record_journey_stage(backend, stage: "queried", duration_ms: 150)
    end

    it "includes form_type tag when provided" do
      expect(backend).to receive(:histogram).with("sec_api.filing.journey.stage_ms", 200, tags: ["stage:extracted", "form_type:10-K"])

      described_class.record_journey_stage(backend, stage: "extracted", duration_ms: 200, form_type: "10-K")
    end

    it "excludes form_type tag when nil" do
      expect(backend).to receive(:histogram).with("sec_api.filing.journey.stage_ms", 100, tags: ["stage:detected"])

      described_class.record_journey_stage(backend, stage: "detected", duration_ms: 100, form_type: nil)
    end

    context "with nil backend" do
      it "does not raise an error" do
        expect { described_class.record_journey_stage(nil, stage: "queried", duration_ms: 150) }.not_to raise_error
      end
    end
  end

  describe ".record_journey_total" do
    it "records total duration histogram with success tag" do
      expect(backend).to receive(:histogram).with("sec_api.filing.journey.total_ms", 5000, tags: ["success:true"])

      described_class.record_journey_total(backend, total_ms: 5000)
    end

    it "includes form_type tag when provided" do
      expect(backend).to receive(:histogram).with("sec_api.filing.journey.total_ms", 3000, tags: ["success:true", "form_type:10-K"])

      described_class.record_journey_total(backend, total_ms: 3000, form_type: "10-K")
    end

    it "records failure with success:false tag" do
      expect(backend).to receive(:histogram).with("sec_api.filing.journey.total_ms", 500, tags: ["success:false"])

      described_class.record_journey_total(backend, total_ms: 500, success: false)
    end

    it "includes both form_type and success tags on failure" do
      expect(backend).to receive(:histogram).with("sec_api.filing.journey.total_ms", 750, tags: ["success:false", "form_type:8-K"])

      described_class.record_journey_total(backend, total_ms: 750, form_type: "8-K", success: false)
    end

    context "with nil backend" do
      it "does not raise an error" do
        expect { described_class.record_journey_total(nil, total_ms: 5000) }.not_to raise_error
      end
    end
  end

  describe "backend compatibility" do
    context "with statsd-ruby backend (no tags support)" do
      let(:simple_backend) { instance_double("StatsD") }

      before do
        allow(simple_backend).to receive(:increment)
        allow(simple_backend).to receive(:histogram)
        allow(simple_backend).to receive(:gauge)
        # statsd-ruby has arity=1 for increment (no tags)
        allow(simple_backend).to receive(:method).with(:increment).and_return(double(arity: 1))
        allow(simple_backend).to receive(:method).with(:histogram).and_return(double(arity: 2))
        allow(simple_backend).to receive(:method).with(:gauge).and_return(double(arity: 2))
      end

      it "calls increment without tags" do
        expect(simple_backend).to receive(:increment).with("sec_api.requests.total")

        described_class.record_response(simple_backend, status: 200, duration_ms: 150, method: :get)
      end
    end

    context "when backend raises an error" do
      before do
        allow(backend).to receive(:increment).and_raise(StandardError, "Connection refused")
      end

      it "swallows the error and does not raise" do
        expect { described_class.record_response(backend, status: 200, duration_ms: 150, method: :get) }.not_to raise_error
      end
    end

    context "when backend does not respond to method" do
      let(:minimal_backend) { Object.new }

      it "does not raise an error" do
        expect { described_class.record_response(minimal_backend, status: 200, duration_ms: 150, method: :get) }.not_to raise_error
      end
    end

    context "with backend that has timing method instead of histogram" do
      let(:timing_backend) { instance_double("TimingStatsD") }

      before do
        allow(timing_backend).to receive(:increment)
        allow(timing_backend).to receive(:timing)
        allow(timing_backend).to receive(:respond_to?).with(:increment).and_return(true)
        allow(timing_backend).to receive(:respond_to?).with(:histogram).and_return(false)
        allow(timing_backend).to receive(:respond_to?).with(:timing).and_return(true)
        allow(timing_backend).to receive(:respond_to?).with(:gauge).and_return(false)
        allow(timing_backend).to receive(:method).with(:increment).and_return(double(arity: 1))
      end

      it "uses timing method as fallback for histogram" do
        expect(timing_backend).to receive(:timing).with("sec_api.requests.duration_ms", 150)

        described_class.record_response(timing_backend, status: 200, duration_ms: 150, method: :get)
      end
    end
  end
end
