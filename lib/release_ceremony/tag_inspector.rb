# frozen_string_literal: true

module ReleaseCeremony
  # Reports where the release tag currently points, locally and on the
  # remote, refusing to guess when the tag data looks unexpected.
  class TagInspector
    TagState = Struct.new(:local_sha, :remote_sha, keyword_init: true)

    def initialize(version:, runner:, remote:)
      @version = version
      @runner = runner
      @remote = remote
    end

    def call
      TagState.new(local_sha: local_tag_sha, remote_sha: remote_tag_sha)
    end

    private

    attr_reader :remote, :runner, :version

    def local_tag_sha
      reference = "refs/tags/#{version.tag}"
      return unless local_tag_exists?(reference)

      resolve_local_tag(reference)
    end

    def local_tag_exists?(reference)
      output = runner.capture('git', 'for-each-ref', '--format=%(refname)', reference)
      return false if output.empty?
      raise Error, "Unexpected local tag data for #{version.tag}" unless output.lines.map(&:strip) == [reference]

      true
    end

    def resolve_local_tag(reference)
      sha = runner.capture('git', 'rev-parse', '--verify', "#{reference}^{commit}").strip
      raise Error, "Local tag #{version.tag} does not resolve to a commit" unless commit_sha?(sha)

      sha
    end

    def remote_tag_sha
      reference = "refs/tags/#{version.tag}"
      output = runner.capture('git', 'ls-remote', '--tags', remote, reference, "#{reference}^{}")
      return if output.empty?

      entries = parse_remote_tag_entries(output, reference)
      entries.fetch("#{reference}^{}", entries[reference])
    end

    def parse_remote_tag_entries(output, reference)
      pairs = output.lines.map { |line| line.strip.split(/\s+/, 2) }
      raise Error, "Unexpected remote tag data for #{version.tag}" unless valid_remote_tag_pairs?(pairs, reference)

      pairs.to_h { |sha, name| [name, sha] }
    end

    def valid_remote_tag_pairs?(pairs, reference)
      names = pairs.map(&:last)
      unique = names.uniq.length == pairs.length
      pairs.all? { |pair| valid_remote_tag_pair?(pair, reference) } && unique && names.include?(reference)
    end

    def valid_remote_tag_pair?(pair, reference)
      sha, name = pair
      commit_sha?(sha) && [reference, "#{reference}^{}"].include?(name)
    end

    def commit_sha?(value)
      value.is_a?(String) && value.match?(/\A[0-9a-f]{40}(?:[0-9a-f]{24})?\z/)
    end
  end
end
