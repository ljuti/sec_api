# frozen_string_literal: true

module SecApi
  # Returns the gem version as a Gem::Version object.
  #
  # @return [Gem::Version] the version of the gem
  #
  # @example
  #   SecApi.gem_version  # => #<Gem::Version "1.0.0">
  #   SecApi.gem_version >= Gem::Version.new("1.0.0")  # => true
  #
  def self.gem_version
    Gem::Version.new(VERSION::STRING)
  end

  # Version information for the sec_api gem.
  #
  # @example Access version string
  #   SecApi::VERSION::STRING  # => "1.0.0"
  #
  # @example Access version components
  #   SecApi::VERSION::MAJOR   # => 1
  #   SecApi::VERSION::MINOR   # => 0
  #   SecApi::VERSION::PATCH   # => 0
  #
  module VERSION
    # @return [Integer] Major version number (breaking changes)
    MAJOR = 1

    # @return [Integer] Minor version number (new features, backwards compatible)
    MINOR = 0

    # @return [Integer] Patch version number (bug fixes)
    PATCH = 1

    # @return [String, nil] Pre-release identifier (e.g., "alpha", "beta", "rc1")
    PRE = nil

    # @return [String] Complete version string (e.g., "0.1.0" or "1.0.0-beta")
    STRING = [MAJOR, MINOR, PATCH, PRE].compact.join(".")
  end
end
