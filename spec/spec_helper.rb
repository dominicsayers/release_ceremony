# frozen_string_literal: true

# SimpleCov
unless ENV['NO_SIMPLECOV']
  require 'simplecov'

  SimpleCov.start do
    add_filter '/spec/'
    enable_coverage :branch

    # Enforced only on full CI runs so partial local runs (a single spec file)
    # do not fail on coverage they never attempted
    minimum_coverage line: 100, branch: 100 if ENV['CI']
  end
end

# Specs
require 'release_ceremony'

RSpec.configure do |config|
  config.run_all_when_everything_filtered = true
  config.order = :random
  Kernel.srand config.seed
end
