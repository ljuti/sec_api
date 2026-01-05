require "faraday"
require "faraday/retry"

module SecApi
  class Client
    def initialize(config = Config.new)
      @_config = config
      @_config.validate!
    end

    def config
      @_config
    end

    def connection
      @_connection ||= build_connection
    end

    private

    def build_connection
      Faraday.new(url: @_config.base_url) do |conn|
        conn.request :json
        conn.response :json, content_type: /\bjson$/, parser_options: {symbolize_names: true}
        # Set API key in Authorization header (redacted from Faraday logs automatically)
        conn.headers["Authorization"] = @_config.api_key
        conn.options.timeout = @_config.request_timeout
        # Retry middleware - retries based on HTTP status codes
        conn.request :retry, retry_options
        # Error handler middleware - converts HTTP errors to typed exceptions
        # NOTE: ErrorHandler skips retryable status codes (429, 500-504) to allow retry
        conn.use Middleware::ErrorHandler
        conn.adapter Faraday.default_adapter
      end
    end

    def query
      @_query ||= Query.new(self)
    end

    def extractor
      @_extractor ||= Extractor.new(self)
    end

    def mapping
      @_mapping ||= Mapping.new(self)
    end

    private

    def retry_options
      {
        max: @_config.retry_max_attempts,
        interval: @_config.retry_initial_delay,
        max_interval: @_config.retry_max_delay,
        backoff_factor: @_config.retry_backoff_factor,
        exceptions: [
          Faraday::TimeoutError,
          Faraday::ConnectionFailed,
          Faraday::SSLError,
          # Catch our typed TransientError exceptions and retry them
          SecApi::TransientError
        ],
        methods: [:get, :post],
        retry_statuses: [429, 500, 502, 503, 504],
        retry_block: ->(env, options, retries, exception) {
          # Called after EACH retry attempt (not just when exhausted)
          # This is for instrumentation/logging only
        }
      }
    end
  end
end
