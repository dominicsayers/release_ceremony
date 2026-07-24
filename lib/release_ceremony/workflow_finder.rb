# frozen_string_literal: true

require 'json'
require 'time'

module ReleaseCeremony
  # Polls GitHub Actions for the workflow run triggered by pushing the
  # release tag, returning its run ID once it appears.
  class WorkflowFinder
    POLL_ATTEMPTS = 12
    POLL_INTERVAL = 5

    def initialize(version:, runner:, sha:, workflow_file:)
      @version = version
      @runner = runner
      @sha = sha
      @workflow_file = workflow_file
    end

    def call
      POLL_ATTEMPTS.times do
        run_id = workflow_run_id(runner.capture(*command))
        return run_id if run_id

        runner.sleep(POLL_INTERVAL)
      end
      raise Error, "Release workflow did not appear for #{sha} after 60 seconds"
    end

    private

    attr_reader :runner, :sha, :version, :workflow_file

    def command
      [
        'gh', 'run', 'list', '--workflow', workflow_file, '--commit', sha, '--event', 'push', '--limit', '100',
        '--json', 'databaseId,headBranch,headSha,event,createdAt'
      ]
    end

    def workflow_run_id(output)
      runs = parse_json(output)
      validate_workflow_runs!(runs)
      matching_runs = runs.select { |run| requested_tag_push?(run) }
      return if matching_runs.empty?

      matching_runs.max_by { |run| Time.iso8601(run.fetch('createdAt')) }.fetch('databaseId')
    end

    def parse_json(output)
      JSON.parse(output)
    rescue JSON::ParserError => e
      raise Error, "Malformed release workflow run JSON: #{e.message}"
    end

    def validate_workflow_runs!(runs)
      raise Error, 'Malformed release workflow run data: expected a JSON array' unless runs.is_a?(Array)
      return if runs.all? { |run| valid_workflow_run?(run) }

      raise Error, 'Release workflow run data is missing a databaseId or valid ref, SHA, event, or createdAt'
    end

    def valid_workflow_run?(run)
      return false unless run.is_a?(Hash)

      id = run['databaseId']
      strings = %w[headBranch headSha event createdAt].map { |key| run[key] }
      id.is_a?(Integer) && id.positive? && strings.all? { |value| present?(value) } && valid_time?(run['createdAt'])
    end

    def valid_time?(value)
      Time.iso8601(value)
      true
    rescue ArgumentError
      false
    end

    def requested_tag_push?(run)
      run['headBranch'] == version.tag && run['headSha'] == sha && run['event'] == 'push'
    end

    def present?(value)
      value.is_a?(String) && !value.empty?
    end
  end
end
