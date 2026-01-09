# frozen_string_literal: true

require "json"

module SecApi
  # Shared helper methods for callback invocation and error handling.
  #
  # This module provides consistent callback error logging across all middleware
  # and client code. All callback invocations should use this module's helpers
  # to ensure consistent structured logging when callbacks fail.
  #
  # @example Including in a middleware class
  #   class MyMiddleware < Faraday::Middleware
  #     include SecApi::CallbackHelper
  #
  #     def call(env)
  #       invoke_callback_safely("my_callback") do
  #         @config.my_callback&.call(data: "value")
  #       end
  #     end
  #   end
  #
  module CallbackHelper
    # Logs callback errors to the configured logger with structured JSON format.
    #
    # @param callback_name [String] Name of the callback that failed
    # @param error [Exception] The exception that was raised
    # @param config [SecApi::Config, nil] Config object with logger (optional)
    # @return [void]
    def log_callback_error(callback_name, error, config = nil)
      # Use instance variable @config if config not passed
      cfg = config || (defined?(@config) ? @config : nil) || (defined?(@_config) ? @_config : nil)
      return unless cfg&.logger

      begin
        cfg.logger.error do
          {
            event: "secapi.callback_error",
            callback: callback_name,
            error_class: error.class.name,
            error_message: error.message
          }.to_json
        end
      rescue
        # Don't let logging errors break anything
      end
    end
  end
end
