# frozen_string_literal: true

require 'fileutils'
require 'spec_helper'
require 'tmpdir'

RSpec.describe ReleaseCeremony::Project do
  let(:root) { Dir.mktmpdir('release-project-spec') }

  after do
    FileUtils.remove_entry(root)
  end

  def write_gemspec(name: 'my_gem', homepage: 'https://github.com/acme/my_gem', extra: '')
    File.write(File.join(root, "#{name}.gemspec"), <<~GEMSPEC)
      Gem::Specification.new do |s|
        s.name = '#{name}'
        s.version = '1.2.2'
        s.summary = 'Spec fixture'
        s.authors = ['Spec']
        s.homepage = '#{homepage}'
        #{extra}
      end
    GEMSPEC
  end

  def write_config(contents)
    File.write(File.join(root, '.release_ceremony.yml'), contents)
  end

  def full_configuration
    <<~YAML
      gem_name: configured_gem
      repo_url: https://github.com/acme/configured
      version_file: VERSION.rb
      changelog_file: HISTORY.md
      workflow_file: publish.yml
      default_branch: trunk
      remote: upstream
      verification_commands:
        - make check
    YAML
  end

  def new_project(**options)
    described_class.new(root: '/repo', gem_name: 'my_gem', repo_url: 'https://github.com/acme/my_gem', **options)
  end

  describe '.load' do
    it 'derives every value from the gemspec and conventions' do
      write_gemspec
      project = described_class.load(root: root)

      expect([project.gem_name, project.repo_url, project.version_file, project.changelog_file])
        .to eq(['my_gem', 'https://github.com/acme/my_gem', 'lib/my_gem/version.rb', 'CHANGELOG.md'])
      expect([project.workflow_file, project.default_branch, project.remote])
        .to eq(['release.yml', 'main', 'origin'])
      expect(project.verification_commands).to eq(described_class::DEFAULT_VERIFICATION_COMMANDS)
    end

    it 'prefers the gemspec source_code_uri over the homepage' do
      write_gemspec(homepage: 'https://acme.example', extra: <<~RUBY)
        s.metadata = { 'source_code_uri' => 'https://github.com/acme/canonical' }
      RUBY

      expect(described_class.load(root: root).repo_url).to eq('https://github.com/acme/canonical')
    end

    it 'strips a trailing slash from the gemspec repository URL' do
      write_gemspec(homepage: 'https://github.com/acme/my_gem/')

      expect(described_class.load(root: root).repo_url).to eq('https://github.com/acme/my_gem')
    end

    it 'derives a nested version file path from a dashed gem name' do
      write_gemspec(name: 'my-gem', homepage: 'https://github.com/acme/my-gem')

      expect(described_class.load(root: root).version_file).to eq('lib/my/gem/version.rb')
    end

    it 'uses configuration overrides without loading any gemspec' do
      write_config(full_configuration)
      project = described_class.load(root: root)

      expect([project.gem_name, project.repo_url, project.version_file, project.changelog_file])
        .to eq(['configured_gem', 'https://github.com/acme/configured', 'VERSION.rb', 'HISTORY.md'])
      expect([project.workflow_file, project.default_branch, project.remote])
        .to eq(['publish.yml', 'trunk', 'upstream'])
      expect(project.verification_commands).to eq([%w[make check]])
    end

    it 'combines a partial configuration with gemspec facts and defaults' do
      write_gemspec
      write_config("default_branch: trunk\n")
      project = described_class.load(root: root)

      expect([project.gem_name, project.default_branch, project.verification_commands])
        .to eq(['my_gem', 'trunk', described_class::DEFAULT_VERIFICATION_COMMANDS])
    end

    it 'splits configured verification commands shell-style' do
      write_gemspec
      write_config(<<~YAML)
        verification_commands:
          - mise exec -- bundle exec rspec
          - echo "hello world"
      YAML

      expect(described_class.load(root: root).verification_commands)
        .to eq([%w[mise exec -- bundle exec rspec], ['echo', 'hello world']])
    end

    it 'requires exactly one gemspec when the configuration is incomplete' do
      expect { described_class.load(root: root) }
        .to raise_error(ReleaseCeremony::Error, /Expected exactly one gemspec.*found 0/)
    end

    it 'rejects an ambiguous choice of gemspecs' do
      write_gemspec
      write_gemspec(name: 'other_gem', homepage: 'https://github.com/acme/other_gem')

      expect { described_class.load(root: root) }
        .to raise_error(ReleaseCeremony::Error, /Expected exactly one gemspec.*found 2/)
    end

    it 'reports a gemspec that does not define a specification' do
      File.write(File.join(root, 'my_gem.gemspec'), "nil\n")

      expect { described_class.load(root: root) }
        .to raise_error(ReleaseCeremony::Error, /Could not load the gemspec/)
    end

    it 'rejects unknown configuration keys' do
      write_config("surprise: true\n")

      expect { described_class.load(root: root) }
        .to raise_error(ReleaseCeremony::Error, /unknown keys: surprise/)
    end

    it 'rejects configuration that is not a YAML mapping' do
      write_config("- 1\n")

      expect { described_class.load(root: root) }
        .to raise_error(ReleaseCeremony::Error, /must contain a YAML mapping/)
    end

    it 'rejects configuration that is not valid YAML' do
      write_config("{invalid\n")

      expect { described_class.load(root: root) }
        .to raise_error(ReleaseCeremony::Error, /is not valid YAML/)
    end

    it 'rejects verification commands that are not a list of strings' do
      ["verification_commands: bundle exec rspec\n", "verification_commands:\n  - 42\n"].each do |contents|
        write_config(contents)

        expect { described_class.load(root: root) }
          .to raise_error(ReleaseCeremony::Error, /verification_commands must be a list of command strings/)
      end
    end

    it 'rejects a verification command with unbalanced quotes' do
      write_gemspec
      write_config(<<~YAML)
        verification_commands:
          - echo "unclosed
      YAML

      expect { described_class.load(root: root) }
        .to raise_error(ReleaseCeremony::Error, /verification_commands entry.*is invalid/)
    end
  end

  describe '.discover' do
    it 'loads the project from the repository the runner reports' do
      write_gemspec
      runner = instance_double(ReleaseCeremony::Runner)
      allow(runner).to receive(:capture).with('git', 'rev-parse', '--show-toplevel').and_return("#{root}\n")

      project = described_class.discover(runner: runner)

      expect([project.root, project.gem_name]).to eq([root, 'my_gem'])
    end
  end

  describe '#initialize' do
    it 'rejects blank or non-string attributes' do
      [{ gem_name: nil }, { default_branch: '' }, { remote: 42 }].each do |options|
        expect { new_project(**options) }
          .to raise_error(ReleaseCeremony::Error, /Project #{options.keys.first} must be a non-empty string/)
      end
    end

    it 'rejects repository URLs that are not GitHub repositories' do
      ['https://gitlab.com/a/b', 'http://github.com/a/b', 'https://github.com/only-owner',
       'https://github.com/a/b/'].each do |repo_url|
        expect { new_project(repo_url: repo_url) }
          .to raise_error(ReleaseCeremony::Error, /repo_url must look like/)
      end
    end

    it 'rejects malformed verification command lists' do
      [[], ['bundle install'], [%w[ok], []], [[42]]].each do |verification_commands|
        expect { new_project(verification_commands: verification_commands) }
          .to raise_error(ReleaseCeremony::Error, /verification_commands must be a list of commands/)
      end
    end
  end

  describe 'derived URLs' do
    it 'builds the changelog comparison base from the repository URL' do
      expect(new_project.compare_base).to eq('https://github.com/acme/my_gem/compare/')
    end

    it 'builds workflow run URLs from the repository URL' do
      expect(new_project.actions_run_url(321)).to eq('https://github.com/acme/my_gem/actions/runs/321')
    end
  end
end
