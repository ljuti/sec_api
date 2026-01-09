# frozen_string_literal: true

require "faye/websocket"
require "eventmachine"
require "json"

module SecApi
  # WebSocket streaming proxy for real-time SEC filing notifications.
  #
  # Connects to sec-api.io's Stream API via WebSocket and delivers
  # filing notifications as they're published to the SEC EDGAR system.
  #
  # @example Subscribe to real-time filings
  #   client = SecApi::Client.new
  #   client.stream.subscribe do |filing|
  #     puts "New filing: #{filing.ticker} - #{filing.form_type}"
  #   end
  #
  # @example Close the streaming connection
  #   stream = client.stream
  #   stream.subscribe { |f| process(f) }
  #   # Later...
  #   stream.close
  #
  # @note The subscribe method blocks while receiving events.
  #   For non-blocking operation, run in a separate thread.
  #
  # @note **Security consideration:** The API key is passed as a URL query
  #   parameter (per sec-api.io Stream API specification). Unlike the REST API
  #   which uses the Authorization header, WebSocket URLs may be logged by
  #   proxies, load balancers, or web server access logs. Ensure your
  #   infrastructure does not log full WebSocket URLs in production.
  #
  # @note **Ping/Pong:** The sec-api.io server sends ping frames every 25 seconds
  #   and expects a pong response within 5 seconds. This is handled automatically
  #   by faye-websocket - no application code is required.
  #
  # @note **Sequential Processing:** Callbacks are invoked synchronously in the
  #   order filings are received. Each callback must complete before the next
  #   filing is processed. This guarantees ordering but means slow callbacks
  #   delay subsequent filings. For high-throughput scenarios, delegate work
  #   to background jobs.
  #
  # @note **Auto-Reconnect:** When the WebSocket connection is lost (network
  #   issues, server restart), the stream automatically attempts to reconnect
  #   using exponential backoff. After 10 failed attempts (by default), a
  #   {ReconnectionError} is raised. Configure via {Config#stream_max_reconnect_attempts},
  #   {Config#stream_initial_reconnect_delay}, {Config#stream_max_reconnect_delay},
  #   and {Config#stream_backoff_multiplier}.
  #
  # @note **Best-Effort Delivery:** Filings published during a disconnection
  #   window are **not** automatically replayed after reconnection. This is a
  #   "best-effort" delivery model. If you require guaranteed delivery, track
  #   the last received filing timestamp and use the Query API to backfill
  #   any gaps after reconnection. See the backfill example below.
  #
  # @note **No Ordering Guarantees During Reconnection:** While connected,
  #   filings arrive in order. However, during a reconnection gap, filings
  #   may be published to EDGAR that your application never sees. After
  #   backfilling, the combined set may not be in strict chronological order.
  #   Sort by filed_at if ordering is critical.
  #
  # @example Tracking last received filing for backfill detection
  #   last_filed_at = nil
  #
  #   client.stream.subscribe do |filing|
  #     last_filed_at = filing.filed_at
  #     process_filing(filing)
  #   end
  #
  # @example Backfilling missed filings after reconnection
  #   disconnect_time = nil
  #   reconnect_time = nil
  #
  #   config = SecApi::Config.new(
  #     api_key: "...",
  #     on_reconnect: ->(info) {
  #       reconnect_time = Time.now
  #       # info[:downtime_seconds] tells you how long you were disconnected
  #       Rails.logger.info("Reconnected after #{info[:downtime_seconds]}s downtime")
  #     }
  #   )
  #
  #   client = SecApi::Client.new(config: config)
  #
  #   # After reconnection, backfill via Query API:
  #   # missed_filings = client.query.filings(
  #   #   filed_from: disconnect_time,
  #   #   filed_to: reconnect_time,
  #   #   tickers: ["AAPL"]  # same filters as stream
  #   # )
  #
  class Stream
    # WebSocket close codes
    CLOSE_NORMAL = 1000
    CLOSE_GOING_AWAY = 1001
    CLOSE_ABNORMAL = 1006
    CLOSE_POLICY_VIOLATION = 1008

    # @return [SecApi::Client] The parent client instance
    attr_reader :client

    # Creates a new Stream proxy.
    #
    # @param client [SecApi::Client] The parent client for config access
    #
    def initialize(client)
      @client = client
      @ws = nil
      @running = false
      @callback = nil
      @tickers = nil
      @form_types = nil
      @mutex = Mutex.new
      # Reconnection state (Story 6.4)
      @reconnect_attempts = 0
      @should_reconnect = true
      @reconnecting = false
      @disconnect_time = nil
    end

    # Subscribe to real-time filing notifications with optional filtering.
    #
    # Establishes a WebSocket connection to sec-api.io's Stream API and
    # invokes the provided block for each filing received. This method
    # blocks while the connection is open.
    #
    # Filtering is performed client-side (sec-api.io streams all filings).
    # When both tickers and form_types are specified, AND logic is applied.
    #
    # @param tickers [Array<String>, String, nil] Filter by ticker symbols (case-insensitive).
    #   Accepts array or single string.
    # @param form_types [Array<String>, String, nil] Filter by form types (case-insensitive).
    #   Amendments are matched (e.g., "10-K" filter matches "10-K/A")
    # @yield [SecApi::Objects::StreamFiling] Block called for each matching filing
    # @return [void]
    # @raise [ArgumentError] when no block is provided
    # @raise [SecApi::NetworkError] on connection failure
    # @raise [SecApi::AuthenticationError] on authentication failure (invalid API key)
    #
    # @example Basic subscription (all filings)
    #   client.stream.subscribe do |filing|
    #     puts "#{filing.ticker}: #{filing.form_type} filed at #{filing.filed_at}"
    #   end
    #
    # @example Filter by tickers
    #   client.stream.subscribe(tickers: ["AAPL", "TSLA"]) do |filing|
    #     puts "#{filing.ticker}: #{filing.form_type}"
    #   end
    #
    # @example Filter by form types
    #   client.stream.subscribe(form_types: ["10-K", "8-K"]) do |filing|
    #     process_material_event(filing)
    #   end
    #
    # @example Combined filters (AND logic)
    #   client.stream.subscribe(tickers: ["AAPL"], form_types: ["10-K", "10-Q"]) do |filing|
    #     analyze_apple_financials(filing)
    #   end
    #
    # @example Non-blocking subscription in separate thread
    #   Thread.new { client.stream.subscribe { |f| queue.push(f) } }
    #
    # @example Sidekiq job enqueueing (AC: #5)
    #   client.stream.subscribe(tickers: ["AAPL"]) do |filing|
    #     # Enqueue job and return quickly - don't block the reactor
    #     ProcessFilingJob.perform_async(filing.accession_no, filing.ticker)
    #   end
    #
    # @example ActiveJob integration (AC: #5)
    #   client.stream.subscribe do |filing|
    #     ProcessFilingJob.perform_later(
    #       accession_no: filing.accession_no,
    #       form_type: filing.form_type
    #     )
    #   end
    #
    # @example Thread pool processing (AC: #5)
    #   pool = Concurrent::ThreadPoolExecutor.new(max_threads: 10)
    #   client.stream.subscribe do |filing|
    #     pool.post { process_filing(filing) }
    #   end
    #
    # @note Callbacks execute synchronously in the EventMachine reactor thread.
    #   Long-running operations should be delegated to background jobs or thread
    #   pools to avoid blocking subsequent filing deliveries. Keep callbacks fast.
    #
    # @note Callback exceptions are caught and logged (if logger configured).
    #   Use {Config#on_callback_error} for custom error handling. The stream
    #   continues processing after callback exceptions.
    #
    def subscribe(tickers: nil, form_types: nil, &block)
      raise ArgumentError, "Block required for subscribe" unless block_given?

      @tickers = normalize_filter(tickers)
      @form_types = normalize_filter(form_types)
      @callback = block
      connect
    end

    # Close the streaming connection.
    #
    # Gracefully closes the WebSocket connection and stops the EventMachine
    # reactor. After closing, no further callbacks will be invoked.
    #
    # @return [void]
    #
    # @example
    #   stream.close
    #   stream.connected? # => false
    #
    def close
      @mutex.synchronize do
        # Prevent reconnection attempts after explicit close
        @should_reconnect = false

        return unless @ws

        @ws.close(CLOSE_NORMAL, "Client requested close")
        @ws = nil
        @running = false
      end
    end

    # Check if the stream is currently connected.
    #
    # @return [Boolean] true if WebSocket connection is open
    #
    def connected?
      @mutex.synchronize do
        @running && @ws && @ws.ready_state == Faye::WebSocket::API::OPEN
      end
    end

    # Returns the current filter configuration.
    #
    # Useful for debugging and monitoring to inspect which filters are active.
    #
    # @return [Hash] Hash with :tickers and :form_types keys
    #
    # @example
    #   stream.subscribe(tickers: ["AAPL"]) { |f| }
    #   stream.filters # => { tickers: ["AAPL"], form_types: nil }
    #
    def filters
      {
        tickers: @tickers,
        form_types: @form_types
      }
    end

    private

    # Establishes WebSocket connection and runs EventMachine reactor.
    #
    # @api private
    def connect
      url = build_url
      @running = true

      EM.run do
        @ws = Faye::WebSocket::Client.new(url)
        setup_handlers
      end
    rescue
      @running = false
      raise
    end

    # Builds the WebSocket URL with API key authentication.
    #
    # @return [String] WebSocket URL
    # @api private
    def build_url
      "wss://stream.sec-api.io?apiKey=#{@client.config.api_key}"
    end

    # Sets up WebSocket event handlers.
    #
    # @api private
    def setup_handlers
      @ws.on :open do |_event|
        @running = true

        if @reconnecting
          # Reconnection succeeded!
          downtime = @disconnect_time ? Time.now - @disconnect_time : 0
          log_reconnect_success(downtime)
          invoke_on_reconnect_callback(@reconnect_attempts, downtime)

          @reconnect_attempts = 0
          @reconnecting = false
          @disconnect_time = nil
        end
      end

      @ws.on :message do |event|
        handle_message(event.data)
      end

      @ws.on :close do |event|
        handle_close(event.code, event.reason)
      end

      @ws.on :error do |event|
        handle_error(event)
      end
    end

    # Handles incoming WebSocket messages.
    #
    # Parses the JSON message containing filing data and invokes
    # the callback for each filing in the array. Callbacks are
    # suppressed after close() has been called.
    #
    # @param data [String] Raw JSON message from WebSocket
    # @api private
    def handle_message(data)
      # Prevent callbacks after close (Task 5 requirement)
      return unless @running

      # Capture receive timestamp FIRST before any processing (Story 6.5, Task 5)
      received_at = Time.now

      filings = JSON.parse(data)
      filings.each do |filing_data|
        # Check again in loop in case close() called during iteration
        break unless @running

        # Pass received_at to constructor (Story 6.5, Task 5)
        filing = Objects::StreamFiling.new(
          transform_keys(filing_data).merge(received_at: received_at)
        )

        # Log filing receipt with latency (Story 6.5, Task 7)
        log_filing_received(filing)

        # Check latency threshold and log warning if exceeded (Story 6.5, Task 8)
        check_latency_threshold(filing)

        # Invoke instrumentation callback (Story 6.5, Task 6)
        invoke_on_filing_callback(filing)

        # Apply filters before callback (Story 6.2)
        next unless matches_filters?(filing)

        invoke_callback_safely(filing)
      end
    rescue JSON::ParserError => e
      # Malformed JSON - log via client logger if available
      log_parse_error("JSON parse error", e)
    rescue Dry::Struct::Error => e
      # Invalid filing data structure - log via client logger if available
      log_parse_error("Filing data validation error", e)
    end

    # Transforms camelCase keys to snake_case symbols.
    #
    # @param hash [Hash] The hash with camelCase keys
    # @return [Hash] Hash with snake_case symbol keys
    # @api private
    def transform_keys(hash)
      hash.transform_keys do |key|
        key.to_s.gsub(/([A-Z])/, '_\1').downcase.delete_prefix("_").to_sym
      end
    end

    # Handles WebSocket close events.
    #
    # Triggers auto-reconnection for abnormal closures when should_reconnect is true.
    # For non-reconnectable closures, raises appropriate errors.
    #
    # @param code [Integer] WebSocket close code
    # @param reason [String] Close reason message
    # @api private
    def handle_close(code, reason)
      was_running = false
      @mutex.synchronize do
        was_running = @running
        @running = false
        @ws = nil
      end

      # Only attempt reconnect if:
      # 1. We were running (not a fresh connection failure)
      # 2. User hasn't called close()
      # 3. It's an abnormal close (not intentional)
      if was_running && @should_reconnect && reconnectable_close?(code)
        @disconnect_time = Time.now
        schedule_reconnect
        return  # Don't stop EM or raise - let reconnection happen
      end

      EM.stop_event_loop if EM.reactor_running?

      case code
      when CLOSE_NORMAL, CLOSE_GOING_AWAY
        # Normal closure - no error
      when CLOSE_POLICY_VIOLATION
        raise AuthenticationError.new(
          message: "WebSocket authentication failed. Verify your API key is valid.",
          status_code: 403
        )
      when CLOSE_ABNORMAL
        raise NetworkError.new(
          message: "WebSocket connection lost unexpectedly. Check network connectivity.",
          original_error: nil
        )
      else
        raise NetworkError.new(
          message: "WebSocket closed with code #{code}: #{reason}",
          original_error: nil
        )
      end
    end

    # Handles WebSocket error events.
    #
    # @param event [Object] Error event from faye-websocket
    # @api private
    def handle_error(event)
      @mutex.synchronize do
        @running = false
        @ws = nil
      end

      EM.stop_event_loop if EM.reactor_running?

      error_message = event.respond_to?(:message) ? event.message : event.to_s
      raise NetworkError.new(
        message: "WebSocket error: #{error_message}",
        original_error: nil
      )
    end

    # Logs message parsing errors via client logger if configured.
    #
    # @param context [String] Description of error context
    # @param error [Exception] The exception that occurred
    # @api private
    def log_parse_error(context, error)
      return unless @client.config.respond_to?(:logger) && @client.config.logger

      log_data = {
        event: "secapi.stream.parse_error",
        context: context,
        error_class: error.class.name,
        error_message: error.message
      }

      begin
        log_level = @client.config.respond_to?(:log_level) ? @client.config.log_level : :warn
        @client.config.logger.send(log_level) { log_data.to_json }
      rescue
        # Don't let logging errors break message processing
      end
    end

    # Invokes the user callback safely, catching and handling any exceptions.
    #
    # When a callback raises an exception, it is logged (if logger configured)
    # and the on_callback_error callback is invoked (if configured). The stream
    # continues processing subsequent filings.
    #
    # @param filing [SecApi::Objects::StreamFiling] The filing to pass to callback
    # @api private
    def invoke_callback_safely(filing)
      @callback.call(filing)
    rescue => e
      log_callback_error(e, filing)
      invoke_on_callback_error(e, filing)
      # Continue processing - don't re-raise
    end

    # Logs callback exceptions via client logger if configured.
    #
    # @param error [Exception] The exception that occurred
    # @param filing [SecApi::Objects::StreamFiling] The filing being processed
    # @api private
    def log_callback_error(error, filing)
      return unless @client.config.logger

      log_data = {
        event: "secapi.stream.callback_error",
        error_class: error.class.name,
        error_message: error.message,
        accession_no: filing.accession_no,
        ticker: filing.ticker,
        form_type: filing.form_type
      }

      begin
        log_level = @client.config.log_level || :error
        @client.config.logger.send(log_level) { log_data.to_json }
      rescue
        # Intentionally empty: logging failures must not break stream processing.
        # The stream's resilience takes priority over error visibility.
      end
    end

    # Invokes the on_callback_error callback if configured.
    #
    # @param error [Exception] The exception that occurred
    # @param filing [SecApi::Objects::StreamFiling] The filing being processed
    # @api private
    def invoke_on_callback_error(error, filing)
      return unless @client.config.on_callback_error

      @client.config.on_callback_error.call(
        error: error,
        filing: filing,
        accession_no: filing.accession_no,
        ticker: filing.ticker
      )
    rescue
      # Intentionally empty: error callback failures must not break stream processing.
      # Prevents meta-errors (errors in error handlers) from crashing the stream.
    end

    # Invokes the on_reconnect callback if configured.
    #
    # Called after a successful reconnection to notify the application of the
    # reconnection event. Exceptions are silently caught to prevent callback
    # errors from disrupting the stream.
    #
    # @param attempt_count [Integer] Number of reconnection attempts before success
    # @param downtime_seconds [Float] Total time disconnected in seconds
    # @api private
    def invoke_on_reconnect_callback(attempt_count, downtime_seconds)
      return unless @client.config.on_reconnect

      @client.config.on_reconnect.call(
        attempt_count: attempt_count,
        downtime_seconds: downtime_seconds
      )
    rescue
      # Intentionally empty: reconnect callback failures must not break stream.
      # The stream must remain operational regardless of callback behavior.
    end

    # Determines if a WebSocket close code indicates a reconnectable failure.
    #
    # Only reconnect for abnormal closure (network issues, server restart).
    # Do NOT reconnect for: normal close, auth failure, policy violation.
    #
    # @param code [Integer] WebSocket close code
    # @return [Boolean] true if reconnection should be attempted
    # @api private
    def reconnectable_close?(code)
      code == CLOSE_ABNORMAL || code.between?(1011, 1015)
    end

    # Schedules a reconnection attempt after the calculated delay.
    #
    # @api private
    def schedule_reconnect
      delay = calculate_reconnect_delay
      log_reconnect_attempt(delay)

      EM.add_timer(delay) do
        attempt_reconnect
      end
    end

    # Attempts to reconnect to the WebSocket server.
    #
    # Increments the attempt counter and creates a new WebSocket connection.
    # If max attempts exceeded, triggers reconnection failure handling.
    #
    # @api private
    def attempt_reconnect
      @reconnect_attempts += 1

      if @reconnect_attempts > @client.config.stream_max_reconnect_attempts
        handle_reconnection_failure
        return
      end

      @reconnecting = true
      @ws = Faye::WebSocket::Client.new(build_url)
      setup_handlers
    end

    # Logs a reconnection attempt.
    #
    # @param delay [Float] Delay in seconds before this attempt
    # @api private
    def log_reconnect_attempt(delay)
      return unless @client.config.logger

      elapsed = @disconnect_time ? Time.now - @disconnect_time : 0
      log_data = {
        event: "secapi.stream.reconnect_attempt",
        attempt: @reconnect_attempts,
        max_attempts: @client.config.stream_max_reconnect_attempts,
        delay: delay.round(2),
        elapsed_seconds: elapsed.round(1)
      }

      begin
        @client.config.logger.info { log_data.to_json }
      rescue
        # Don't let logging errors break reconnection
      end
    end

    # Logs a successful reconnection.
    #
    # @param downtime [Float] Total downtime in seconds
    # @api private
    def log_reconnect_success(downtime)
      return unless @client.config.logger

      log_data = {
        event: "secapi.stream.reconnect_success",
        attempts: @reconnect_attempts,
        downtime_seconds: downtime.round(1)
      }

      begin
        @client.config.logger.info { log_data.to_json }
      rescue
        # Don't let logging errors break reconnection
      end
    end

    # Logs filing receipt with latency information (Story 6.5, Task 7).
    #
    # @param filing [Objects::StreamFiling] The received filing
    # @api private
    def log_filing_received(filing)
      return unless @client.config.logger

      log_data = {
        event: "secapi.stream.filing_received",
        accession_no: filing.accession_no,
        ticker: filing.ticker,
        form_type: filing.form_type,
        latency_ms: filing.latency_ms,
        received_at: filing.received_at.iso8601(3)
      }

      begin
        @client.config.logger.info { log_data.to_json }
      rescue
        # Don't let logging errors break stream processing
      end
    end

    # Checks latency against threshold and logs warning if exceeded (Story 6.5, Task 8).
    #
    # @param filing [Objects::StreamFiling] The received filing
    # @api private
    def check_latency_threshold(filing)
      return unless @client.config.logger
      return unless filing.latency_seconds

      threshold = @client.config.stream_latency_warning_threshold
      return if filing.latency_seconds <= threshold

      log_data = {
        event: "secapi.stream.latency_warning",
        accession_no: filing.accession_no,
        ticker: filing.ticker,
        form_type: filing.form_type,
        latency_ms: filing.latency_ms,
        threshold_seconds: threshold
      }

      begin
        @client.config.logger.warn { log_data.to_json }
      rescue
        # Don't let logging errors break stream processing
      end
    end

    # Invokes the on_filing instrumentation callback (Story 6.5, Task 6).
    #
    # @param filing [Objects::StreamFiling] The received filing
    # @api private
    def invoke_on_filing_callback(filing)
      return unless @client.config.on_filing

      begin
        @client.config.on_filing.call(
          filing: filing,
          latency_ms: filing.latency_ms,
          received_at: filing.received_at
        )
      rescue => e
        # Don't let callback errors break stream processing
        # Optionally log the error
        log_on_filing_callback_error(filing, e)
      end
    end

    # Logs errors from on_filing callback.
    #
    # @param filing [Objects::StreamFiling] The filing that caused the error
    # @param error [Exception] The error that was raised
    # @api private
    def log_on_filing_callback_error(filing, error)
      return unless @client.config.logger

      log_data = {
        event: "secapi.stream.on_filing_callback_error",
        accession_no: filing.accession_no,
        ticker: filing.ticker,
        error_class: error.class.name,
        error_message: error.message
      }

      begin
        @client.config.logger.warn { log_data.to_json }
      rescue
        # Don't let logging errors break stream processing
      end
    end

    # Handles reconnection failure after maximum attempts exceeded.
    #
    # @api private
    def handle_reconnection_failure
      @running = false
      @reconnecting = false
      EM.stop_event_loop if EM.reactor_running?

      downtime = @disconnect_time ? Time.now - @disconnect_time : 0
      raise ReconnectionError.new(
        message: "WebSocket reconnection failed after #{@reconnect_attempts} attempts " \
                 "(#{downtime.round(1)}s downtime). Check network connectivity.",
        attempts: @reconnect_attempts,
        downtime_seconds: downtime
      )
    end

    # Calculates delay before next reconnection attempt using exponential backoff.
    #
    # Formula: min(initial * (multiplier ^ attempt), max_delay) * jitter
    # Jitter adds +-10% randomness to prevent thundering herd when multiple
    # clients reconnect simultaneously.
    #
    # @return [Float] Delay in seconds before next attempt
    # @api private
    def calculate_reconnect_delay
      config = @client.config
      base_delay = config.stream_initial_reconnect_delay *
        (config.stream_backoff_multiplier**@reconnect_attempts)
      capped_delay = [base_delay, config.stream_max_reconnect_delay].min

      # Add jitter: random value between 0.9 and 1.1 of the delay
      jitter_factor = 0.9 + rand * 0.2
      capped_delay * jitter_factor
    end

    # Normalizes filter to uppercase strings for case-insensitive matching.
    #
    # Accepts an array of strings or a single string value. Single values
    # are wrapped in an array for convenience. Duplicates are removed.
    #
    # @param filter [Array<String>, String, nil] Filter value(s)
    # @return [Array<String>, nil] Normalized uppercase array, or nil if empty/nil
    # @api private
    def normalize_filter(filter)
      return nil if filter.nil?

      # Convert to array (handles single string input)
      values = Array(filter)
      return nil if values.empty?

      values.map { |f| f.to_s.upcase }.uniq
    end

    # Checks if filing matches all configured filters (AND logic).
    #
    # @param filing [SecApi::Objects::StreamFiling] The filing to check
    # @return [Boolean] true if filing passes all filters
    # @api private
    def matches_filters?(filing)
      matches_ticker_filter?(filing) && matches_form_type_filter?(filing)
    end

    # Checks if filing matches the ticker filter.
    #
    # @param filing [SecApi::Objects::StreamFiling] The filing to check
    # @return [Boolean] true if filing passes the ticker filter
    # @api private
    def matches_ticker_filter?(filing)
      return true if @tickers.nil?  # No filter = pass all

      ticker = filing.ticker&.upcase
      return true if ticker.nil?  # No ticker in filing = pass through

      @tickers.include?(ticker)
    end

    # Checks if filing matches the form_type filter.
    #
    # Amendments are handled specially: a filter for "10-K" will match both
    # "10-K" and "10-K/A" filings. However, a filter for "10-K/A" only matches
    # "10-K/A", not "10-K".
    #
    # @param filing [SecApi::Objects::StreamFiling] The filing to check
    # @return [Boolean] true if filing passes the form_type filter
    # @api private
    def matches_form_type_filter?(filing)
      return true if @form_types.nil?  # No filter = pass all

      form_type = filing.form_type&.upcase
      return false if form_type.nil?  # No form type = filter out

      # Match exact or base form type (10-K/A matches 10-K filter)
      @form_types.any? do |filter|
        form_type == filter || form_type.start_with?("#{filter}/")
      end
    end
  end
end
