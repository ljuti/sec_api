# frozen_string_literal: true

module SecApi
  # Raised when WebSocket reconnection fails after maximum attempts.
  #
  # This is a TransientError (the underlying cause was likely temporary)
  # but after exhausting retries, we give up and surface to the caller.
  #
  # @example Handling reconnection failure
  #   begin
  #     client.stream.subscribe { |f| process(f) }
  #   rescue SecApi::ReconnectionError => e
  #     logger.error("Stream failed permanently", attempts: e.attempts)
  #     # Fallback to polling via Query API
  #   end
  #
  class ReconnectionError < NetworkError
    # @return [Integer] Number of reconnection attempts made
    attr_reader :attempts

    # @return [Float] Total downtime in seconds
    attr_reader :downtime_seconds

    # @param message [String] Error message
    # @param attempts [Integer] Number of reconnection attempts made
    # @param downtime_seconds [Float] Total downtime in seconds
    def initialize(message:, attempts:, downtime_seconds:)
      @attempts = attempts
      @downtime_seconds = downtime_seconds
      super(message: message, original_error: nil)
    end
  end
end
