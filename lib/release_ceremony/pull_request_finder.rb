# frozen_string_literal: true

require 'json'

module ReleaseCeremony
  # Finds the single merged pull request for the release branch and extracts
  # its merge commit, refusing ambiguous or malformed data.
  class PullRequestFinder
    PR_LIMIT = '100'
    PullRequest = Struct.new(:number, :url, :sha, keyword_init: true)

    def initialize(version:, runner:, project:)
      @version = version
      @runner = runner
      @project = project
    end

    def call
      pull_requests = parse_json(runner.capture(*command))
      ensure_one_pull_request!(pull_requests)
      extract_pull_request(pull_requests.first)
    end

    private

    attr_reader :project, :runner, :version

    def command
      [
        'gh', 'pr', 'list', '--state', 'merged', '--base', project.default_branch, '--head', "release-v#{version}",
        '--json', 'number,url,mergeCommit,mergedAt', '--limit', PR_LIMIT
      ]
    end

    def ensure_one_pull_request!(pull_requests)
      raise Error, 'Malformed merged pull request data: expected a JSON array' unless pull_requests.is_a?(Array)
      return if pull_requests.one?

      raise Error, "Expected exactly one merged release-v#{version} pull request; found #{pull_requests.length}"
    end

    def extract_pull_request(pull_request)
      attributes = pull_request_attributes(pull_request)
      unless attributes
        raise Error, 'Merged pull request data is missing a number, URL, merge time, or merge commit SHA'
      end

      PullRequest.new(number: attributes.fetch(0), url: attributes.fetch(1), sha: attributes.fetch(3))
    end

    def pull_request_attributes(pull_request)
      return unless pull_request.is_a?(Hash)

      merge_commit = pull_request['mergeCommit']
      sha = merge_commit['oid'] if merge_commit.is_a?(Hash)
      attributes = [
        pull_request['number'], pull_request['url'], pull_request['mergedAt'], sha
      ]
      attributes if valid_pull_request_attributes?(*attributes)
    end

    def valid_pull_request_attributes?(number, url, merged_at, sha)
      number.is_a?(Integer) && number.positive? && present?(url) && present?(merged_at) && commit_sha?(sha)
    end

    def parse_json(output)
      JSON.parse(output)
    rescue JSON::ParserError => e
      raise Error, "Malformed merged pull request JSON: #{e.message}"
    end

    def present?(value)
      value.is_a?(String) && !value.empty?
    end

    def commit_sha?(value)
      value.is_a?(String) && value.match?(/\A[0-9a-f]{40}(?:[0-9a-f]{24})?\z/)
    end
  end
end
