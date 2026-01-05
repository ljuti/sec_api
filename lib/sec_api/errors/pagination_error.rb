# frozen_string_literal: true

module SecApi
  # Raised when a pagination operation cannot be completed.
  #
  # This error is raised when attempting to fetch the next page of results
  # when no more pages are available. It inherits from PermanentError because
  # retrying the operation will not resolve the issue.
  #
  # @example Handling pagination end
  #   begin
  #     next_page = filings.fetch_next_page
  #   rescue SecApi::PaginationError => e
  #     puts "No more pages available"
  #   end
  #
  # @example Checking before fetching
  #   if filings.has_more?
  #     next_page = filings.fetch_next_page
  #   else
  #     puts "Already on the last page"
  #   end
  #
  # @see SecApi::Collections::Filings#fetch_next_page
  # @see SecApi::Collections::Filings#has_more?
  class PaginationError < PermanentError
  end
end
