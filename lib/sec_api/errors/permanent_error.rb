# frozen_string_literal: true

module SecApi
  # Base class for all non-retryable (permanent) errors.
  #
  # Design rationale: PermanentError signals the retry middleware to fail immediately
  # without retrying. Retrying a 401 (bad API key) or 404 (nonexistent resource) wastes
  # resources and delays the inevitable failure. Fail fast with a clear message instead.
  #
  # These errors require human intervention - code changes, configuration fixes,
  # or different input parameters. The same request will always fail.
  #
  # Permanent errors represent failures that won't be resolved by retrying,
  # such as authentication failures, validation errors, or resource not found.
  # These errors require code or configuration changes to resolve.
  #
  # @example Catching all permanent errors
  #   begin
  #     client.query.ticker("INVALID").search
  #   rescue SecApi::PermanentError => e
  #     # No retry will help - requires action
  #     logger.error("Permanent failure: #{e.message}")
  #     notify_developer(e)
  #   end
  #
  # @see TransientError for retryable errors
  class PermanentError < Error
  end
end
