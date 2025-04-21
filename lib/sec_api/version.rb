# frozen_string_literal: true

module SecApi
  def self.gem_version
    Gem::Version.new(VERSION::STRING)
  end

  # The version of the sec_api gem.
  #
  # @return [String] the version of the gem
  # @see SecApi.gem_version
  module VERSION
    MAJOR = 0
    MINOR = 1
    PATCH = 0
    PRE = nil # :nodoc:

    STRING = [MAJOR, MINOR, PATCH, PRE].compact.join(".")
  end
end
