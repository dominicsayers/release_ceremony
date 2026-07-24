# frozen_string_literal: true

require 'date'
require 'shellwords'

module ReleaseCeremony
  # Prepares a release on its release-vVERSION branch: updates the version
  # file, dates the changelog, and runs the verification commands. Never
  # commits or pushes.
  class Prepare
    extend Command

    USAGE = 'Usage: release_ceremony prepare VERSION'
    HELP = <<~TEXT.freeze
      #{USAGE}

      Prepare VERSION on its release-vVERSION branch, update the release files,
      and run the release checks. This command does not commit or push changes.
    TEXT
    VERSION_DECLARATION = /^[ \t]*VERSION[ \t]*=/
    VERSION_ASSIGNMENT = /^(?<indent>[ \t]*)VERSION = '(?<current>[^'\r\n]+)'[ \t]*$/

    def initialize(version:, runner:, project: nil, today: Date.today, writer: TransactionalWriter.new)
      @version = version
      @runner = runner
      @project = project || Project.discover(runner: runner)
      @today = today
      @writer = writer
    end

    def call
      Dir.chdir(project.root) { prepare_release }
      print_next_steps
      true
    rescue SystemCallError => e
      raise Error, e.message
    end

    private

    attr_reader :project, :runner, :today, :version, :writer

    def prepare_release
      announce('Checking the release branch and working tree')
      guard_repository!
      announce("Updating #{project.version_file} and #{project.changelog_file}")
      version_contents, current_version = transformed_version_file
      write_release_files(version_contents, transformed_changelog(current_version))
      run_verification_commands
    end

    def announce(message)
      runner.puts("#{message}...")
    end

    def guard_repository!
      branch = runner.capture('git', 'symbolic-ref', '--quiet', '--short', 'HEAD').strip
      expected_branch = "release-v#{version}"
      raise Error, "Current branch must be #{expected_branch}, not #{branch}" unless branch == expected_branch

      status = runner.capture('git', 'status', '--porcelain=v1')
      raise Error, 'Working tree must be clean before preparing a release' unless status.empty?
    end

    def transformed_version_file
      contents = File.binread(project.version_file)
      assignment = version_assignment(contents)
      current_version = parse_current_version(assignment[:current])
      raise Error, "Version #{version} must be greater than #{current_version}" unless version > current_version

      replacement = "#{assignment[:indent]}VERSION = '#{version}'"
      [contents.sub(VERSION_ASSIGNMENT, replacement), current_version]
    end

    def version_assignment(contents)
      declarations = contents.lines.grep(VERSION_DECLARATION)
      assignment = VERSION_ASSIGNMENT.match(declarations.first.to_s)
      message = "#{project.version_file} must contain exactly one VERSION assignment"
      raise Error, message unless declarations.one? && assignment

      assignment
    end

    def parse_current_version(value)
      Semver.parse(value)
    rescue Error
      raise Error, "Current VERSION must use the X.Y.Z format, not #{value.inspect}"
    end

    def transformed_changelog(current_version)
      Changelog.new(
        contents: File.binread(project.changelog_file),
        current_version: current_version,
        version: version,
        today: today,
        compare_base: project.compare_base,
        changelog_file: project.changelog_file
      ).transform
    end

    def write_release_files(version_contents, changelog_contents)
      writer.write(project.version_file => version_contents, project.changelog_file => changelog_contents)
    end

    def run_verification_commands
      project.verification_commands.each do |command|
        announce("Running: #{Shellwords.join(command)}")
        runner.run(*command)
      end
    end

    def print_next_steps
      runner.puts("Prepared version #{version} and completed the release checks.")
      runner.puts('Inspect the changes, then commit and push the release branch.')
      runner.puts("Open and merge the pull request before running release_ceremony publish #{version}.")
    end
  end
end
