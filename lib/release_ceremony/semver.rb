# frozen_string_literal: true

require 'rubygems/version'

module ReleaseCeremony
  # A strict X.Y.Z release version: no prereleases, no leading zeroes.
  class Semver
    include Comparable

    PATTERN = /\A(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\z/
    ERROR_MESSAGE = 'Version must use the X.Y.Z format'

    class << self
      def parse(value)
        raise Error, ERROR_MESSAGE unless value.is_a?(String) && PATTERN.match?(value)

        new(value)
      end

      private :new
    end

    def initialize(value)
      @value = value
      @gem_version = Gem::Version.new(value)
    end

    def <=>(other)
      return unless other.is_a?(self.class)

      gem_version <=> other.gem_version
    end

    def to_s
      value
    end

    def tag
      "v#{value}"
    end

    protected

    attr_reader :gem_version

    private

    attr_reader :value
  end
end
