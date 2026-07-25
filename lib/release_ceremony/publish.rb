# frozen_string_literal: true

module ReleaseCeremony
  # Publishes a prepared, merged release: validates the merge commit, tags
  # it, pushes the tag, watches the tag-triggered release workflow, and
  # confirms the gem appears on RubyGems.
  class Publish
    extend Command

    USAGE = 'Usage: release_ceremony publish VERSION'
    HELP = <<~TEXT.freeze
      #{USAGE}

      Validate and publish the merged release-vVERSION pull request by tagging
      its merge commit and monitoring the release workflow.
    TEXT

    def initialize(version:, runner:, project: nil)
      @version = version
      @runner = runner
      @project = project || Project.discover(runner: runner)
    end

    def call
      runner.run('git', 'fetch', '--no-tags', project.remote, project.default_branch)
      pull_request = merged_pull_request
      sha = pull_request.sha
      validate_release_commit!(sha)
      tags = tag_state
      validate_existing_tags!(tags, sha)
      print_summary(pull_request, tags)
      confirm!
      publish_tag(tags, sha)
      monitor_release(sha)
      true
    end

    private

    attr_reader :project, :runner, :version

    def merged_pull_request
      PullRequestFinder.new(version: version, runner: runner, project: project).call
    end

    def remote_branch
      "#{project.remote}/#{project.default_branch}"
    end

    def validate_release_commit!(sha)
      validate_ancestry!(sha)
      validate_version_file!(runner.capture('git', 'show', "#{sha}:#{project.version_file}"))
      validate_changelog!(runner.capture('git', 'show', "#{sha}:#{project.changelog_file}"))
    end

    def validate_ancestry!(sha)
      runner.run('git', 'merge-base', '--is-ancestor', sha, remote_branch)
    rescue Error
      raise Error, "Merge commit #{sha} is not an ancestor of #{remote_branch}"
    end

    def validate_version_file!(contents)
      assignments = contents.lines.grep(/^[ \t]*VERSION[ \t]*=/)
      expected = /^[ \t]*VERSION = '#{Regexp.escape(version.to_s)}'[ \t]*$/
      return if assignments.one? && assignments.first.match?(expected)

      raise Error, "#{project.version_file} at the merge commit does not assign VERSION = '#{version}' exactly"
    end

    def validate_changelog!(contents)
      return if changelog_heading?(contents) && changelog_link?(contents)

      raise Error,
            "#{project.changelog_file} at the merge commit lacks the exact #{version} heading or comparison link"
    end

    def changelog_heading?(contents)
      heading = /^## \[#{Regexp.escape(version.to_s)}\] - \d{4}-\d{2}-\d{2}[ \t]*$/
      contents.lines.grep(heading).one?
    end

    def changelog_link?(contents)
      link = /^\[#{Regexp.escape(version.to_s)}\]:[ ]#{Regexp.escape(project.compare_base)}
               v\d+\.\d+\.\d+\.\.\.v#{Regexp.escape(version.to_s)}[ \t]*$/x
      contents.lines.grep(link).one?
    end

    def tag_state
      TagInspector.new(version: version, runner: runner, remote: project.remote).call
    end

    def validate_existing_tags!(tags, sha)
      validate_existing_tag!('Local', tags.local_sha, sha)
      validate_existing_tag!('Remote', tags.remote_sha, sha)
    end

    def validate_existing_tag!(location, existing_sha, expected_sha)
      return unless existing_sha
      return if existing_sha == expected_sha

      raise Error, "#{location} tag #{version.tag} points to #{existing_sha}, not merge commit #{expected_sha}"
    end

    def print_summary(pull_request, tags)
      summary_lines(pull_request, tags).each { |line| runner.puts(line) }
    end

    def summary_lines(pull_request, tags)
      [
        "Merged pull request: ##{pull_request.number} #{pull_request.url}",
        "Merge commit: #{pull_request.sha}",
        "Tag: #{version.tag}",
        "Local tag: #{tag_description(tags.local_sha)}",
        "Remote tag: #{tag_description(tags.remote_sha)}"
      ]
    end

    def tag_description(sha)
      sha ? "exists at #{sha}" : 'absent'
    end

    def confirm!
      expected = "publish #{version.tag}"
      runner.print("Type '#{expected}' to continue: ")
      return if runner.gets&.chomp == expected

      raise Error, 'Publication cancelled; no tag was created or pushed'
    end

    def publish_tag(tags, sha)
      return if tags.remote_sha

      runner.run('git', 'tag', version.tag, sha) unless tags.local_sha
      runner.run('git', 'push', project.remote, version.tag)
    end

    def monitor_release(sha)
      run_id = find_workflow_run(sha)
      runner.puts('The release uses a protected environment; approve it in GitHub if prompted.')
      open_workflow_run(run_id)
      runner.run('gh', 'run', 'watch', run_id.to_s, '--exit-status')
      verify_published_gem!
    end

    def open_workflow_run(run_id)
      runner.run('gh', 'run', 'view', run_id.to_s, '--web')
    rescue Error => e
      message = [
        "Could not open run #{run_id} in a browser: #{e.message}.",
        "Visit #{project.actions_run_url(run_id)} or run gh run view #{run_id} --web."
      ].join(' ')
      runner.warn(message)
    end

    def find_workflow_run(sha)
      WorkflowFinder.new(version: version, runner: runner, sha: sha, workflow_file: project.workflow_file).call
    end

    def verify_published_gem!
      unless published_versions.include?(version.to_s)
        raise Error, "RubyGems does not list #{project.gem_name} version #{version}"
      end

      runner.puts("Published #{project.gem_name} #{version} successfully.")
    end

    def published_versions
      output = runner.capture('gem', 'list', '--remote', '--exact', project.gem_name, '--all')
      output.lines
            .filter_map { |line| line[/\A#{Regexp.escape(project.gem_name)} \(([^)]+)\)/, 1] }
            .flat_map { |list| list.split(',').map(&:strip) }
    end
  end
end
