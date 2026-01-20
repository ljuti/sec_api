# frozen_string_literal: true

require_relative "lib/sec_api/version"

Gem::Specification.new do |spec|
  spec.name = "sec_api"
  spec.version = SecApi.gem_version
  spec.authors = ["Lauri Jutila"]
  spec.email = ["git@laurijutila.com"]

  spec.summary = "Ruby client for sec-api.io"
  spec.description = "Ruby client for accessing SEC EDGAR filings through the sec-api.io API."
  spec.homepage = "https://github.com/ljuti/sec_api"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/ljuti/sec_api"
  spec.metadata["changelog_uri"] = "https://github.com/ljuti/sec_api/blob/main/CHANGELOG.md"

  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Uncomment to register a new dependency of your gem
  # spec.add_dependency "example-gem", "~> 1.0"
  spec.add_dependency "faraday"
  spec.add_dependency "faraday-retry"
  spec.add_dependency "anyway_config"
  spec.add_dependency "dry-struct"
  spec.add_dependency "faye-websocket", "~> 0.11"
  spec.add_dependency "eventmachine", "~> 1.2"

  # Development dependencies
  spec.add_development_dependency "yard", "~> 0.9"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
