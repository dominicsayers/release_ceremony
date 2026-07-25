# frozen_string_literal: true

require_relative 'lib/release_ceremony/version'

Gem::Specification.new do |s|
  s.name          = 'release_ceremony'
  s.version       = ReleaseCeremony::VERSION
  s.authors       = ['Dominic Sayers']
  s.email         = ['dominic@sayers.cc']
  s.summary       = 'A strict, verified release ceremony for RubyGems projects hosted on GitHub'
  s.description   = 'Command-line tools that prepare a release on its release branch (version bump, ' \
                    'changelog update, verification checks) and publish the merged release pull request ' \
                    'by tagging its merge commit and monitoring the tag-triggered release workflow'
  s.homepage      = 'https://github.com/dominicsayers/release_ceremony'
  s.license       = 'MIT'

  s.required_ruby_version = '>= 3.1.0'

  # A deterministic whitelist: runtime code plus user-facing documentation.
  # Development configuration is deliberately not packaged.
  s.files = Dir.glob('lib/**/*.rb', base: __dir__).sort +
            Dir.glob('exe/*', base: __dir__).sort +
            %w[CHANGELOG.md LICENSE README.md]
  s.bindir = 'exe'
  s.executables = ['release_ceremony']
  s.require_paths = ['lib']

  s.metadata = {
    'bug_tracker_uri' => "#{s.homepage}/issues",
    'changelog_uri' => "#{s.homepage}/blob/main/CHANGELOG.md",
    'homepage_uri' => s.homepage,
    'source_code_uri' => s.homepage,
    'rubygems_mfa_required' => 'true'
  }
end
