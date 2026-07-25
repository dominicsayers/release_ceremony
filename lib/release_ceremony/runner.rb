# frozen_string_literal: true

require 'open3'
require 'shellwords'

module ReleaseCeremony
  # Runs external commands without a shell and mediates all console
  # interaction, so command execution and I/O can be faked in tests.
  class Runner
    def initialize(stdout: $stdout, stderr: $stderr, stdin: $stdin, sleeper: Kernel)
      @stdout = stdout
      @stderr = stderr
      @stdin = stdin
      @sleeper = sleeper
    end

    def capture(*command)
      validate_command!(command)
      captured_stdout, captured_stderr, status = unbundled { Open3.capture3(*command) }
      return captured_stdout if status.success?

      raise_command_error(command, captured_stderr)
    rescue SystemCallError => e
      raise_spawn_error(command, e.message)
    end

    def run(*command)
      validate_command!(command)
      result = unbundled { system(*command) }
      return true if result

      result.nil? ? raise_spawn_error(command) : raise_command_error(command)
    rescue SystemCallError => e
      raise_spawn_error(command, e.message)
    end

    def puts(message = '')
      @stdout.puts(message)
    end

    def print(message)
      @stdout.print(message)
    end

    def warn(message)
      @stderr.puts(message)
    end

    def gets
      @stdin.gets
    end

    def sleep(duration)
      @sleeper.sleep(duration)
    end

    private

    # The ceremony normally runs under bundle exec, but its child processes
    # must not inherit that Bundler context: a nested bundle command crashes
    # when RUBYOPT and the BUNDLE_* variables point at the ceremony's own
    # bundle instead of the repository being released
    def unbundled(&)
      return yield unless bundler_loaded?

      Bundler.with_unbundled_env(&)
    end

    def bundler_loaded?
      !defined?(Bundler).nil?
    end

    def validate_command!(command)
      return if command.length > 1 && command.all?(String)

      raise Error, 'Command must be provided as an executable and separate arguments'
    end

    def raise_command_error(command, captured_stderr = nil)
      message = "Command failed: #{Shellwords.join(command.map(&:to_s))}"
      message = "#{message}\n#{captured_stderr.strip}" unless captured_stderr.to_s.strip.empty?
      raise Error, message
    end

    def raise_spawn_error(command, details = 'Executable was not found')
      message = "Command could not be executed: #{Shellwords.join(command.map(&:to_s))}"
      raise Error, "#{message}\n#{details}"
    end
  end
end
