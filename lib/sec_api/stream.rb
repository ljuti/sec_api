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
      @mutex = Mutex.new
    end

    # Subscribe to real-time filing notifications.
    #
    # Establishes a WebSocket connection to sec-api.io's Stream API and
    # invokes the provided block for each filing received. This method
    # blocks while the connection is open.
    #
    # @yield [SecApi::Objects::StreamFiling] Block called for each filing
    # @return [void]
    # @raise [ArgumentError] when no block is provided
    # @raise [SecApi::NetworkError] on connection failure
    # @raise [SecApi::AuthenticationError] on authentication failure (invalid API key)
    #
    # @example Basic subscription
    #   client.stream.subscribe do |filing|
    #     puts "#{filing.ticker}: #{filing.form_type} filed at #{filing.filed_at}"
    #   end
    #
    # @example Non-blocking subscription in separate thread
    #   Thread.new { client.stream.subscribe { |f| queue.push(f) } }
    #
    def subscribe(&block)
      raise ArgumentError, "Block required for subscribe" unless block_given?

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
        # Connection established, ready to receive filings
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

      filings = JSON.parse(data)
      filings.each do |filing_data|
        # Check again in loop in case close() called during iteration
        break unless @running

        filing = Objects::StreamFiling.new(transform_keys(filing_data))
        @callback.call(filing)
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
    # @param code [Integer] WebSocket close code
    # @param reason [String] Close reason message
    # @api private
    def handle_close(code, reason)
      @mutex.synchronize do
        @running = false
        @ws = nil
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
  end
end
