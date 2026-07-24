# frozen_string_literal: true

require 'shellwords'
require 'yaml'

module ReleaseCeremony
  # The repository-specific facts the release ceremony needs: the gem name,
  # the release file paths, the GitHub repository URL, and the verification
  # commands. Project.load reads overrides from .release_ceremony.yml and
  # falls back to the repository's gemspec and conventional defaults.
  class Project
    CONFIG_FILE = '.release_ceremony.yml'
    CONFIG_KEYS = %w[gem_name repo_url version_file changelog_file verification_commands
                     workflow_file default_branch remote].freeze
    REPO_URL_PATTERN = %r{\Ahttps://github\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+\z}
    DEFAULT_VERIFICATION_COMMANDS = [
      %w[bundle install],
      %w[bundle exec rspec],
      %w[bundle exec rubocop],
      %w[bundle exec rake build]
    ].freeze

    attr_reader :root, :gem_name, :repo_url, :version_file, :changelog_file,
                :verification_commands, :workflow_file, :default_branch, :remote

    class << self
      def discover(runner: Runner.new)
        load(root: runner.capture('git', 'rev-parse', '--show-toplevel').strip)
      end

      def load(root:)
        config = Config.read(root)
        gemspec = GemspecFacts.new(root)
        overrides = config.slice('version_file', 'changelog_file', 'verification_commands',
                                 'workflow_file', 'default_branch', 'remote').transform_keys(&:to_sym)
        new(
          root: root,
          gem_name: config.fetch('gem_name') { gemspec.name },
          repo_url: config.fetch('repo_url') { gemspec.repo_url },
          **overrides
        )
      end
    end

    def initialize(root:, gem_name:, repo_url:, version_file: nil, changelog_file: nil,
                   verification_commands: nil, workflow_file: nil, default_branch: nil, remote: nil)
      @root = validated_string(:root, root)
      @gem_name = validated_string(:gem_name, gem_name)
      @repo_url = validated_repo_url(repo_url)
      @version_file = validated_string(:version_file, version_file || default_version_file)
      @changelog_file = validated_string(:changelog_file, changelog_file || 'CHANGELOG.md')
      @verification_commands = validated_commands(verification_commands || DEFAULT_VERIFICATION_COMMANDS)
      @workflow_file = validated_string(:workflow_file, workflow_file || 'release.yml')
      @default_branch = validated_string(:default_branch, default_branch || 'main')
      @remote = validated_string(:remote, remote || 'origin')
    end

    def compare_base
      "#{repo_url}/compare/"
    end

    def actions_run_url(run_id)
      "#{repo_url}/actions/runs/#{run_id}"
    end

    private

    def default_version_file
      "lib/#{gem_name.tr('-', '/')}/version.rb"
    end

    def validated_string(name, value)
      raise Error, "Project #{name} must be a non-empty string" unless value.is_a?(String) && !value.empty?

      value
    end

    def validated_repo_url(value)
      validated_string(:repo_url, value)
      unless REPO_URL_PATTERN.match?(value)
        raise Error, "Project repo_url must look like https://github.com/OWNER/REPO, not #{value.inspect}"
      end

      value
    end

    def validated_commands(commands)
      valid = commands.is_a?(Array) && !commands.empty? &&
              commands.all? { |command| command.is_a?(Array) && !command.empty? && command.all?(String) }
      raise Error, 'Project verification_commands must be a list of commands, each a list of strings' unless valid

      commands
    end

    # Reads and validates the optional .release_ceremony.yml overrides.
    module Config
      extend self

      def read(root)
        path = File.join(root, CONFIG_FILE)
        return {} unless File.exist?(path)

        config = parse(path)
        unknown = config.keys - CONFIG_KEYS
        raise Error, "#{CONFIG_FILE} has unknown keys: #{unknown.join(', ')}" unless unknown.empty?

        parse_verification_commands(config)
      end

      private

      def parse(path)
        config = YAML.safe_load_file(path)
        raise Error, "#{CONFIG_FILE} must contain a YAML mapping" unless config.is_a?(Hash)

        config
      rescue Psych::Exception => e
        raise Error, "#{CONFIG_FILE} is not valid YAML: #{e.message}"
      end

      def parse_verification_commands(config)
        return config unless config.key?('verification_commands')

        commands = config['verification_commands']
        valid = commands.is_a?(Array) && commands.all?(String)
        raise Error, "#{CONFIG_FILE} verification_commands must be a list of command strings" unless valid

        config.merge('verification_commands' => commands.map { |command| split_command(command) })
      end

      def split_command(command)
        Shellwords.split(command)
      rescue ArgumentError => e
        raise Error, "#{CONFIG_FILE} verification_commands entry #{command.inspect} is invalid: #{e.message}"
      end
    end

    # Lazily extracts facts from the repository's gemspec, so a fully
    # configured project never needs to load it.
    class GemspecFacts
      def initialize(root)
        @root = root
      end

      def name
        specification.name
      end

      def repo_url
        url = specification.metadata['source_code_uri'] || specification.homepage
        url.to_s.chomp('/')
      end

      private

      def specification
        @specification ||= load_specification
      end

      def load_specification
        path = gemspec_path
        Gem::Specification.load(path) || raise(Error, "Could not load the gemspec at #{path}")
      end

      def gemspec_path
        paths = Dir.glob('*.gemspec', base: @root).sort
        raise Error, "Expected exactly one gemspec in #{@root}; found #{paths.length}" unless paths.one?

        File.join(@root, paths.first)
      end
    end
  end
end
