# frozen_string_literal: true

module ReleaseCeremony
  # Shared entry point behaviour for the ceremony commands: --help handling
  # and strict VERSION argument parsing.
  module Command
    def run(arguments, runner: Runner.new, **options)
      if arguments == ['--help']
        runner.puts(self::HELP)
        return true
      end

      new(version: parse_version(arguments), runner: runner, **options).call
    end

    private

    def parse_version(arguments)
      raise Error, self::USAGE unless arguments.length == 1

      Semver.parse(arguments.first)
    rescue Error => e
      raise if e.message == self::USAGE

      raise Error, "#{e.message}\n#{self::USAGE}"
    end
  end
end
