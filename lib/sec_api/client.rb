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

    def query
      @_query ||= Query.new(self)
    end

    def extractor
      @_extractor ||= Extractor.new(self)
    end

    def mapping
      @_mapping ||= Mapping.new(self)
    end

    # Returns the XBRL extraction proxy for accessing XBRL-to-JSON conversion functionality.
    #
    # @return [SecApi::Xbrl] XBRL proxy instance with access to client's Faraday connection
    #
    # @example Extract XBRL data from a filing
    #   client = SecApi::Client.new(api_key: "your_api_key")
    #   xbrl_data = client.xbrl.to_json(filing)
    #   xbrl_data.financials[:revenue]  # => 394328000000.0
    #
    def xbrl
      @_xbrl ||= Xbrl.new(self)
    end

    private

    def build_connection
      Faraday.new(url: @_config.base_url) do |conn|
        # Set API key in Authorization header (redacted from Faraday logs automatically)
        conn.headers["Authorization"] = @_config.api_key
        conn.options.timeout = @_config.request_timeout

        # JSON encoding/decoding
        conn.request :json
        conn.response :json, content_type: /\bjson$/, parser_options: {symbolize_names: true}

        # Retry middleware - positioned BEFORE ErrorHandler to catch HTTP status codes
        # Retries on [429, 500, 502, 503, 504] and Faraday exceptions
        conn.request :retry, retry_options

        # Error handler middleware - converts HTTP errors to typed exceptions
        # Positioned AFTER retry so non-retryable errors (401, 404, etc.) fail immediately
        conn.use Middleware::ErrorHandler

        # Connection pool configuration (NFR14: minimum 10 concurrent requests)
        # Note: Net::HTTP adapter uses persistent connections but doesn't expose pool_size config
        # The adapter handles concurrent requests via Ruby's thread-safe HTTP implementation
        conn.adapter Faraday.default_adapter
      end
    end

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
          # Basic logging - users can configure @_config.on_retry callback for custom instrumentation
          if @_config.respond_to?(:on_retry) && @_config.on_retry
            @_config.on_retry.call(env, exception, retries)
          end
        }
      }
    end
  end
end
