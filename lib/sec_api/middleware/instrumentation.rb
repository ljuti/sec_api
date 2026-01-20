# frozen_string_literal: true

require "faraday"
require "securerandom"

module SecApi
  module Middleware
    # Faraday middleware that provides instrumentation callbacks for request/response lifecycle.
    #
    # This middleware captures request timing and invokes configurable callbacks for:
    # - on_request: Before the request is sent (for logging, tracing)
    # - on_response: After the response is received (for metrics, latency tracking)
    # - on_error: When request ultimately fails after all retries exhausted (for error tracking)
    #
    # Position in middleware stack: FIRST (before Retry, RateLimiter, ErrorHandler)
    # This ensures all requests are instrumented, including retried requests.
    # Being first also allows capturing exceptions after all retries are exhausted.
    #
    # @example Basic usage with config callbacks
    #   config = SecApi::Config.new(
    #     api_key: "...",
    #     on_request: ->(request_id:, method:, url:, headers:) { log_request(request_id) },
    #     on_response: ->(request_id:, status:, duration_ms:, url:, method:) { track_metrics(duration_ms) }
    #   )
    #   client = SecApi::Client.new(config)
    #
    # @example Using external request_id for distributed tracing
    #   # Create custom middleware to inject trace ID from your APM system
    #   class TraceIdMiddleware < Faraday::Middleware
    #     def call(env)
    #       # Use existing trace ID from Datadog, New Relic, OpenTelemetry, etc.
    #       # Falls back to SecureRandom.uuid if no trace ID is available
    #       env[:request_id] = Datadog.tracer.active_span&.span_id ||
    #                          RequestStore[:request_id] ||
    #                          SecureRandom.uuid
    #       @app.call(env)
    #     end
    #   end
    #
    #   # Register BEFORE sec_api Instrumentation middleware
    #   Faraday.new do |conn|
    #     conn.use TraceIdMiddleware           # Sets env[:request_id]
    #     conn.use SecApi::Middleware::Instrumentation  # Preserves via ||=
    #     # ... rest of stack
    #   end
    #
    # @example Correlating errors with APM spans
    #   SecApi.configure do |config|
    #     config.on_error = ->(request_id:, error:, **) {
    #       if span = Datadog.tracer.active_span
    #         span.set_tag('sec_api.request_id', request_id)
    #         span.set_error(error)
    #       end
    #     }
    #   end
    #
    # @note Authorization headers are automatically sanitized from on_request callbacks
    #   to prevent API key leakage in logs.
    #
    # @note External request_id: If you pre-set env[:request_id] via upstream middleware,
    #   this middleware will preserve it (uses ||= operator). This enables distributed
    #   tracing integration with Datadog, New Relic, OpenTelemetry, and Rails request IDs.
    #
    class Instrumentation < Faraday::Middleware
      include SecApi::CallbackHelper

      # Initializes the instrumentation middleware.
      #
      # @param app [Faraday::Middleware] The next middleware in the stack
      # @param options [Hash] Configuration options
      # @option options [SecApi::Config] :config The config object containing callbacks
      def initialize(app, options = {})
        super(app)
        @config = options[:config]
      end

      # Processes the request and invokes instrumentation callbacks.
      #
      # @param env [Faraday::Env] The request environment
      # @return [Faraday::Response] The response from downstream middleware
      def call(env)
        # Generate request_id if not already set (allows upstream middleware to set it)
        env[:request_id] ||= SecureRandom.uuid

        # Capture start time using monotonic clock for accurate duration.
        # Why monotonic? Time.now can jump backward (NTP sync, DST) causing negative durations.
        # CLOCK_MONOTONIC is guaranteed to increase, essential for accurate latency metrics.
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        # Invoke on_request callback BEFORE request is sent
        invoke_on_request(env)

        # Execute the request through downstream middleware
        @app.call(env).on_complete do |response_env|
          # Calculate duration in milliseconds
          end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          duration_ms = ((end_time - start_time) * 1000).round

          # Store duration in env for potential use by other middleware
          response_env[:duration_ms] = duration_ms

          # Invoke on_response callback AFTER response is received
          invoke_on_response(response_env, duration_ms)
        end
      rescue SecApi::Error => e
        # Invoke on_error callback for errors that escape after all retries exhausted.
        # This catches both TransientError (NetworkError, ServerError, RateLimitError)
        # and PermanentError (AuthenticationError, NotFoundError, ValidationError).
        # PermanentError on_error is also invoked by ErrorHandler for immediate failures,
        # but we invoke here too for consistency (both paths call on_error exactly once).
        # Note: ErrorHandler only invokes on_error for PermanentError, not TransientError.
        invoke_on_error(env, e)
        raise
      end

      private

      # Invokes the on_request callback if configured.
      #
      # @param env [Faraday::Env] The request environment
      # @return [void]
      def invoke_on_request(env)
        return unless @config&.on_request

        @config.on_request.call(
          request_id: env[:request_id],
          method: env[:method],
          url: env[:url].to_s,
          headers: sanitize_headers(env[:request_headers])
        )
      rescue => e
        log_callback_error("on_request", e)
      end

      # Invokes the on_response callback if configured.
      #
      # @param env [Faraday::Env] The response environment
      # @param duration_ms [Integer] Request duration in milliseconds
      # @return [void]
      def invoke_on_response(env, duration_ms)
        return unless @config&.on_response

        @config.on_response.call(
          request_id: env[:request_id],
          status: env[:status],
          duration_ms: duration_ms,
          url: env[:url].to_s,
          method: env[:method]
        )
      rescue => e
        log_callback_error("on_response", e)
      end

      # Invokes the on_error callback if configured.
      # Called when a request ultimately fails (after all retries exhausted).
      #
      # @param env [Faraday::Env] The request environment
      # @param error [SecApi::Error] The error that caused the failure
      # @return [void]
      def invoke_on_error(env, error)
        return unless @config&.on_error

        @config.on_error.call(
          request_id: env[:request_id],
          error: error,
          url: env[:url].to_s,
          method: env[:method]
        )
      rescue => e
        log_callback_error("on_error", e)
      end

      # Removes sensitive headers (Authorization) from the headers hash.
      #
      # @param headers [Hash, nil] Request headers
      # @return [Hash] Headers with sensitive values removed
      def sanitize_headers(headers)
        return {} unless headers

        headers.reject { |k, _| k.to_s.downcase == "authorization" }
      end

      # log_callback_error is provided by CallbackHelper module
    end
  end
end
