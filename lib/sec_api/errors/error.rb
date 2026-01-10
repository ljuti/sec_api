module SecApi
  # Base error class for all sec_api errors.
  #
  # All errors include a request_id for correlation with logs and
  # instrumentation callbacks. When request_id is present, error messages
  # are automatically prefixed with `[request_id]` for easy log correlation.
  #
  # @example Accessing request_id from error
  #   begin
  #     client.query.ticker("AAPL").search
  #   rescue SecApi::Error => e
  #     logger.error("Request failed", request_id: e.request_id, error: e.message)
  #     Bugsnag.notify(e, request_id: e.request_id)
  #   end
  #
  # @example Error message format with request_id
  #   # When request_id is present:
  #   # => "[abc123-def456] Rate limit exceeded (429 Too Many Requests)."
  #   #
  #   # When request_id is nil or empty:
  #   # => "Rate limit exceeded (429 Too Many Requests)."
  #
  # @example Correlating with distributed tracing
  #   begin
  #     client.query.ticker("AAPL").search
  #   rescue SecApi::Error => e
  #     # The request_id matches the trace ID from your APM system
  #     # if you configured external request_id via custom middleware
  #     Datadog.tracer.active_span&.set_tag('sec_api.request_id', e.request_id)
  #   end
  #
  class Error < StandardError
    # The unique request correlation ID for this error.
    # @return [String, nil] UUID request ID, or nil if not available
    attr_reader :request_id

    # Creates a new error with optional request correlation ID.
    #
    # @param message [String] Error message
    # @param request_id [String, nil] Request correlation ID for tracing
    def initialize(message = nil, request_id: nil)
      @request_id = request_id
      super(build_message(message))
    end

    private

    # Builds the error message, optionally prefixing with request_id.
    #
    # @param message [String, nil] Original error message
    # @return [String, nil] Formatted message with request_id prefix if present
    def build_message(message)
      return message if @request_id.nil? || @request_id.to_s.empty?
      "[#{@request_id}] #{message}"
    end
  end
end
