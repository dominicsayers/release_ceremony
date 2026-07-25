# frozen_string_literal: true

module ReleaseCeremony
  # Command-line entry point that dispatches to the ceremony commands.
  class CLI
    USAGE = 'Usage: release_ceremony prepare|publish VERSION'
    HELP = <<~TEXT.freeze
      #{USAGE}

      Commands:
        prepare VERSION  Update the release files on the release branch and run the checks.
        publish VERSION  Tag the merged release pull request and watch the release workflow.

      Run release_ceremony COMMAND --help for details of each command.
    TEXT
    COMMANDS = { 'prepare' => Prepare, 'publish' => Publish }.freeze

    def self.run(arguments, runner: Runner.new, **options)
      command, *command_arguments = arguments
      if command == '--help'
        runner.puts(HELP)
        return true
      end

      handler = COMMANDS.fetch(command) do
        raise Error, command ? "Unknown command #{command.inspect}\n#{USAGE}" : USAGE
      end
      handler.run(command_arguments, runner: runner, **options)
    end
  end
end
