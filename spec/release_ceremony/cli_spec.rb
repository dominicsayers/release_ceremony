# frozen_string_literal: true

require 'bundler'
require 'open3'
require 'rbconfig'
require 'stringio'
require 'spec_helper'

RSpec.describe ReleaseCeremony::CLI do
  let(:stdout) { StringIO.new }
  let(:runner) { ReleaseCeremony::Runner.new(stdout: stdout, stderr: StringIO.new, stdin: StringIO.new) }

  describe '.run' do
    it 'shows the top-level help' do
      result = described_class.run(['--help'], runner: runner)

      expect([result, stdout.string]).to eq([true, described_class::HELP])
    end

    it 'rejects a missing command with usage guidance' do
      expect { described_class.run([], runner: runner) }
        .to raise_error(ReleaseCeremony::Error, described_class::USAGE)
    end

    it 'rejects an unknown command with usage guidance' do
      expect { described_class.run(%w[deploy 1.2.3], runner: runner) }
        .to raise_error(ReleaseCeremony::Error, /Unknown command "deploy".*Usage: release_ceremony/m)
    end

    it 'dispatches prepare with the remaining arguments' do
      result = described_class.run(%w[prepare --help], runner: runner)

      expect([result, stdout.string]).to eq([true, ReleaseCeremony::Prepare::HELP])
    end

    it 'dispatches publish with the remaining arguments' do
      result = described_class.run(%w[publish --help], runner: runner)

      expect([result, stdout.string]).to eq([true, ReleaseCeremony::Publish::HELP])
    end

    it 'surfaces usage errors from the dispatched command' do
      expect { described_class.run(['prepare'], runner: runner) }
        .to raise_error(ReleaseCeremony::Error, /Usage: release_ceremony prepare VERSION/)
    end
  end

  describe 'executable entry point' do
    it 'has executable permission' do
      expect(File.executable?(executable)).to be(true)
    end

    it 'prints help successfully without errors' do
      output, errors, status = run_executable('--help')

      expect([status.success?, output, errors]).to eq([true, described_class::HELP, ''])
    end

    it 'reports usage errors concisely with a non-zero exit status' do
      output, errors, status = run_executable

      expect([status.success?, output, errors])
        .to match([false, '', /Error:.*Usage: release_ceremony/m])
    end

    it 'reports unknown commands concisely with a non-zero exit status' do
      output, errors, status = run_executable('deploy', '1.2.3')

      expect([status.success?, output, errors]).to match([false, '', /Error: Unknown command "deploy"/])
    end

    def executable
      File.expand_path('../../exe/release_ceremony', __dir__)
    end

    # An unbundled environment keeps Bundler's RUBYOPT out of the child
    # process, whose stderr must contain only the executable's own output.
    def run_executable(*arguments)
      lib = File.expand_path('../../lib', __dir__)
      Bundler.with_unbundled_env { Open3.capture3(RbConfig.ruby, '-I', lib, executable, *arguments) }
    end
  end
end
