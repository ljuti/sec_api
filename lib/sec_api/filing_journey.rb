# frozen_string_literal: true

module SecApi
  # Tracks filing lifecycle from detection through processing.
  #
  # Use accession_no as the correlation key to trace a filing through
  # all processing stages: detection -> query -> extraction -> processing.
  #
  # == Correlation Key: accession_no
  #
  # The SEC accession number (accession_no) uniquely identifies each filing and
  # serves as the primary correlation key across all journey stages. This enables:
  #
  # - Tracing a filing's complete journey through your system
  # - Correlating stream events with subsequent API calls
  # - Debugging failed pipelines by filtering logs on accession_no
  # - Measuring end-to-end latency for specific filings
  #
  # == Log Query Patterns
  #
  # === ELK Stack / Kibana
  #
  #   # Find all journey events for a specific filing:
  #   accession_no:"0000320193-24-000001" AND event:secapi.filing.journey.*
  #
  #   # Find filings that failed processing:
  #   event:secapi.filing.journey.processed AND success:false
  #
  #   # Find slow extractions (>500ms):
  #   event:secapi.filing.journey.extracted AND duration_ms:>500
  #
  # === Datadog Logs
  #
  #   # All journey stages for a filing:
  #   @accession_no:0000320193-24-000001 @event:secapi.filing.journey.*
  #
  #   # Failed pipelines:
  #   @event:secapi.filing.journey.processed @success:false
  #
  #   # 10-K filings detected:
  #   @event:secapi.filing.journey.detected @form_type:10-K
  #
  # === CloudWatch Logs Insights
  #
  #   fields @timestamp, event, stage, accession_no, duration_ms
  #   | filter accession_no = "0000320193-24-000001"
  #   | filter event like /secapi\.filing\.journey/
  #   | sort @timestamp asc
  #
  # === Splunk
  #
  #   index=production sourcetype=ruby_json
  #   | spath event
  #   | search event="secapi.filing.journey.*"
  #   | search accession_no="0000320193-24-000001"
  #   | table _time event stage duration_ms
  #
  # == Correlating Stream -> Query -> Extraction
  #
  # The accession_no flows through all stages, enabling correlation:
  #
  #   1. Stream Detection: on_filing receives StreamFiling with accession_no
  #   2. Query Lookup: Use accession_no to find full filing metadata
  #   3. XBRL Extraction: Pass filing with accession_no to xbrl.to_json
  #   4. Processing: Track processing completion with same accession_no
  #
  # All log entries share the same accession_no, allowing you to reconstruct
  # the complete journey in your log aggregation tool.
  #
  # @example Complete pipeline tracking with logging
  #   logger = Rails.logger
  #
  #   # Stage 1: Filing detected via stream
  #   stream.subscribe do |filing|
  #     FilingJourney.log_detected(logger, :info,
  #       accession_no: filing.accession_no,
  #       ticker: filing.ticker,
  #       form_type: filing.form_type
  #     )
  #
  #     # Stage 2: Query for additional metadata
  #     result = client.query.ticker(filing.ticker).form_type(filing.form_type).limit(1).find
  #     FilingJourney.log_queried(logger, :info,
  #       accession_no: filing.accession_no,
  #       found: result.any?
  #     )
  #
  #     # Stage 3: Extract XBRL data
  #     xbrl_data = client.xbrl.to_json(filing)
  #     FilingJourney.log_extracted(logger, :info,
  #       accession_no: filing.accession_no,
  #       facts_count: xbrl_data.facts&.size || 0
  #     )
  #
  #     # Stage 4: Process the data
  #     ProcessFilingJob.perform_async(filing.accession_no)
  #   end
  #
  # @example Using accession_no for log correlation (ELK query)
  #   # Kibana query to see complete journey:
  #   # accession_no:"0000320193-24-000001" AND event:secapi.filing.journey.*
  #
  # @example Measuring pipeline latency
  #   detected_at = Time.now
  #   # ... processing ...
  #   processed_at = Time.now
  #
  #   FilingJourney.log_processed(logger, :info,
  #     accession_no: filing.accession_no,
  #     total_duration_ms: ((processed_at - detected_at) * 1000).round
  #   )
  #
  # @example Complete pipeline with stage timing and metrics
  #   class FilingPipeline
  #     def initialize(client, logger, metrics_backend = nil)
  #       @client = client
  #       @logger = logger
  #       @metrics = metrics_backend
  #     end
  #
  #     def start_streaming(tickers:, form_types:)
  #       @client.stream.subscribe(tickers: tickers, form_types: form_types) do |filing|
  #         process_filing(filing)
  #       end
  #     end
  #
  #     private
  #
  #     def process_filing(filing)
  #       detected_at = Time.now
  #       accession_no = filing.accession_no
  #
  #       # Stage 1: Log detection with stream latency
  #       SecApi::FilingJourney.log_detected(@logger, :info,
  #         accession_no: accession_no,
  #         ticker: filing.ticker,
  #         form_type: filing.form_type,
  #         latency_ms: filing.latency_ms
  #       )
  #
  #       # Stage 2: Query for full filing details (with timing)
  #       query_start = Time.now
  #       full_filing = @client.query
  #         .ticker(filing.ticker)
  #         .form_type(filing.form_type)
  #         .limit(1)
  #         .find
  #         .first
  #       query_duration = SecApi::FilingJourney.calculate_duration_ms(query_start)
  #
  #       SecApi::FilingJourney.log_queried(@logger, :info,
  #         accession_no: accession_no,
  #         found: !full_filing.nil?,
  #         duration_ms: query_duration
  #       )
  #       SecApi::MetricsCollector.record_journey_stage(@metrics,
  #         stage: "queried",
  #         duration_ms: query_duration,
  #         form_type: filing.form_type
  #       ) if @metrics
  #
  #       # Stage 3: Extract XBRL data (with timing)
  #       extract_start = Time.now
  #       xbrl_data = @client.xbrl.to_json(filing)
  #       extract_duration = SecApi::FilingJourney.calculate_duration_ms(extract_start)
  #
  #       SecApi::FilingJourney.log_extracted(@logger, :info,
  #         accession_no: accession_no,
  #         facts_count: xbrl_data&.facts&.size || 0,
  #         duration_ms: extract_duration
  #       )
  #       SecApi::MetricsCollector.record_journey_stage(@metrics,
  #         stage: "extracted",
  #         duration_ms: extract_duration,
  #         form_type: filing.form_type
  #       ) if @metrics
  #
  #       # Stage 4: Enqueue for processing
  #       total_duration = SecApi::FilingJourney.calculate_duration_ms(detected_at)
  #       ProcessFilingJob.perform_async(accession_no, xbrl_data.to_h)
  #
  #       SecApi::FilingJourney.log_processed(@logger, :info,
  #         accession_no: accession_no,
  #         success: true,
  #         total_duration_ms: total_duration
  #       )
  #       SecApi::MetricsCollector.record_journey_total(@metrics,
  #         total_ms: total_duration,
  #         form_type: filing.form_type,
  #         success: true
  #       ) if @metrics
  #
  #     rescue => e
  #       total_duration = SecApi::FilingJourney.calculate_duration_ms(detected_at)
  #
  #       SecApi::FilingJourney.log_processed(@logger, :error,
  #         accession_no: accession_no,
  #         success: false,
  #         total_duration_ms: total_duration,
  #         error_class: e.class.name
  #       )
  #       SecApi::MetricsCollector.record_journey_total(@metrics,
  #         total_ms: total_duration,
  #         form_type: filing.form_type,
  #         success: false
  #       ) if @metrics
  #
  #       raise
  #     end
  #   end
  #
  # @example Sidekiq background job with journey tracking
  #   class ProcessFilingWorker
  #     include Sidekiq::Worker
  #
  #     def perform(accession_no, filing_data)
  #       start_time = Time.now
  #       logger = Sidekiq.logger
  #
  #       # Track the processing stage (final stage of journey)
  #       result = process_filing_data(filing_data)
  #
  #       # Log completion (this is the user processing stage)
  #       duration = SecApi::FilingJourney.calculate_duration_ms(start_time)
  #       SecApi::FilingJourney.log_processed(logger, :info,
  #         accession_no: accession_no,
  #         success: true,
  #         total_duration_ms: duration
  #       )
  #
  #       result
  #     rescue => e
  #       duration = SecApi::FilingJourney.calculate_duration_ms(start_time)
  #       SecApi::FilingJourney.log_processed(logger, :error,
  #         accession_no: accession_no,
  #         success: false,
  #         total_duration_ms: duration,
  #         error_class: e.class.name
  #       )
  #       raise
  #     end
  #
  #     private
  #
  #     def process_filing_data(data)
  #       # Your business logic here
  #     end
  #   end
  #
  module FilingJourney
    extend self

    # Journey Stage Constants
    #
    # Filing pipeline stages follow a consistent naming convention:
    #
    # - `detected`  - Filing received via WebSocket stream (on_filing callback)
    # - `queried`   - Filing metadata fetched via Query API (on_response callback)
    # - `extracted` - XBRL data extracted via XBRL API (on_response callback)
    # - `processed` - User processing complete (custom callback in application code)
    #
    # Event Naming Convention:
    #   secapi.filing.journey.<stage>
    #
    # Examples:
    #   secapi.filing.journey.detected
    #   secapi.filing.journey.queried
    #   secapi.filing.journey.extracted
    #   secapi.filing.journey.processed
    #
    # @see STAGE_DETECTED
    # @see STAGE_QUERIED
    # @see STAGE_EXTRACTED
    # @see STAGE_PROCESSED

    # Filing detected via WebSocket stream
    STAGE_DETECTED = "detected"

    # Filing metadata fetched via Query API
    STAGE_QUERIED = "queried"

    # XBRL data extracted via XBRL API
    STAGE_EXTRACTED = "extracted"

    # User processing complete (application-defined)
    STAGE_PROCESSED = "processed"

    # Logs filing detection from stream.
    #
    # @param logger [Logger] Logger instance
    # @param level [Symbol] Log level (:debug, :info, :warn, :error)
    # @param accession_no [String] SEC accession number (correlation key)
    # @param ticker [String, nil] Stock ticker symbol
    # @param form_type [String, nil] Filing form type
    # @param latency_ms [Integer, nil] Stream delivery latency
    # @return [void]
    #
    # @example Basic detection logging
    #   FilingJourney.log_detected(logger, :info,
    #     accession_no: "0000320193-24-000001",
    #     ticker: "AAPL",
    #     form_type: "10-K"
    #   )
    #
    def log_detected(logger, level, accession_no:, ticker: nil, form_type: nil, latency_ms: nil)
      log_stage(logger, level, STAGE_DETECTED, {
        accession_no: accession_no,
        ticker: ticker,
        form_type: form_type,
        latency_ms: latency_ms
      }.compact)
    end

    # Logs filing query/lookup completion.
    #
    # @param logger [Logger] Logger instance
    # @param level [Symbol] Log level
    # @param accession_no [String] SEC accession number (correlation key)
    # @param found [Boolean, nil] Whether filing was found
    # @param request_id [String, nil] Request correlation ID
    # @param duration_ms [Integer, nil] Query duration in milliseconds
    # @return [void]
    #
    # @example Query logging
    #   FilingJourney.log_queried(logger, :info,
    #     accession_no: "0000320193-24-000001",
    #     found: true,
    #     duration_ms: 150
    #   )
    #
    def log_queried(logger, level, accession_no:, found: nil, request_id: nil, duration_ms: nil)
      log_stage(logger, level, STAGE_QUERIED, {
        accession_no: accession_no,
        found: found,
        request_id: request_id,
        duration_ms: duration_ms
      }.compact)
    end

    # Logs XBRL data extraction completion.
    #
    # @param logger [Logger] Logger instance
    # @param level [Symbol] Log level
    # @param accession_no [String] SEC accession number (correlation key)
    # @param facts_count [Integer, nil] Number of XBRL facts extracted
    # @param request_id [String, nil] Request correlation ID
    # @param duration_ms [Integer, nil] Extraction duration in milliseconds
    # @return [void]
    #
    # @example Extraction logging
    #   FilingJourney.log_extracted(logger, :info,
    #     accession_no: "0000320193-24-000001",
    #     facts_count: 42,
    #     duration_ms: 200
    #   )
    #
    def log_extracted(logger, level, accession_no:, facts_count: nil, request_id: nil, duration_ms: nil)
      log_stage(logger, level, STAGE_EXTRACTED, {
        accession_no: accession_no,
        facts_count: facts_count,
        request_id: request_id,
        duration_ms: duration_ms
      }.compact)
    end

    # Logs filing processing completion.
    #
    # @param logger [Logger] Logger instance
    # @param level [Symbol] Log level
    # @param accession_no [String] SEC accession number (correlation key)
    # @param success [Boolean] Whether processing succeeded (default: true)
    # @param total_duration_ms [Integer, nil] Total pipeline duration in milliseconds
    # @param error_class [String, nil] Error class name if processing failed
    # @return [void]
    #
    # @example Successful processing
    #   FilingJourney.log_processed(logger, :info,
    #     accession_no: "0000320193-24-000001",
    #     success: true,
    #     total_duration_ms: 5000
    #   )
    #
    # @example Failed processing
    #   FilingJourney.log_processed(logger, :error,
    #     accession_no: "0000320193-24-000001",
    #     success: false,
    #     total_duration_ms: 500,
    #     error_class: "RuntimeError"
    #   )
    #
    def log_processed(logger, level, accession_no:, success: true, total_duration_ms: nil, error_class: nil)
      log_stage(logger, level, STAGE_PROCESSED, {
        accession_no: accession_no,
        success: success,
        total_duration_ms: total_duration_ms,
        error_class: error_class
      }.compact)
    end

    # Calculates duration between two timestamps.
    #
    # Use this method for both stage-to-stage timing and total pipeline duration.
    # The method returns milliseconds for consistency with other duration fields.
    #
    # @param start_time [Time] Start timestamp
    # @param end_time [Time] End timestamp (defaults to current time)
    # @return [Integer] Duration in milliseconds
    #
    # @example Calculate stage duration (stage-to-stage)
    #   query_start = Time.now
    #   result = client.query.ticker("AAPL").find
    #   query_duration = FilingJourney.calculate_duration_ms(query_start)
    #
    #   FilingJourney.log_queried(logger, :info,
    #     accession_no: accession_no,
    #     duration_ms: query_duration
    #   )
    #
    # @example Calculate total pipeline duration (end-to-end)
    #   detected_at = Time.now
    #   # ... all pipeline stages ...
    #   total = FilingJourney.calculate_duration_ms(detected_at)
    #
    #   FilingJourney.log_processed(logger, :info,
    #     accession_no: accession_no,
    #     total_duration_ms: total
    #   )
    #
    # @example Calculate deltas from logs (ELK/Kibana)
    #   # Each log entry includes ISO8601 timestamp:
    #   # {"event":"secapi.filing.journey.detected","timestamp":"2024-01-15T10:30:00.000Z",...}
    #   # {"event":"secapi.filing.journey.queried","timestamp":"2024-01-15T10:30:00.150Z",...}
    #   #
    #   # Kibana Timelion query for average stage duration:
    #   # .es(index=logs, q='event:secapi.filing.journey.queried', metric=avg:duration_ms)
    #   #
    #   # Elasticsearch aggregation for stage timing:
    #   # {
    #   #   "aggs": {
    #   #     "by_stage": {
    #   #       "terms": { "field": "stage.keyword" },
    #   #       "aggs": {
    #   #         "avg_duration": { "avg": { "field": "duration_ms" } }
    #   #       }
    #   #     }
    #   #   }
    #   # }
    #
    def calculate_duration_ms(start_time, end_time = Time.now)
      ((end_time - start_time) * 1000).round
    end

    private

    # Writes a structured log event for a journey stage.
    #
    # @param logger [Logger] Logger instance
    # @param level [Symbol] Log level
    # @param stage [String] Journey stage name
    # @param data [Hash] Event data
    # @return [void]
    # @api private
    def log_stage(logger, level, stage, data)
      return unless logger

      log_data = {
        event: "secapi.filing.journey.#{stage}",
        stage: stage,
        timestamp: Time.now.utc.iso8601(3)
      }.merge(data)

      logger.send(level) { log_data.to_json }
    rescue
      # Don't let logging errors break the processing flow
    end
  end
end
