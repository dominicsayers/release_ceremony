# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ReleaseCeremony::Semver do
  let(:invalid_versions) do
    [
      '1.2',
      'v1.2.3',
      '01.2.3',
      '1.02.3',
      '1.2.03',
      '1.2.3-rc1',
      '1.2.3+build.1',
      12_003,
      nil
    ]
  end

  describe '.parse' do
    it 'accepts stable semantic versions without leading zeroes' do
      expect(described_class.parse('0.1.23').to_s).to eq('0.1.23')
    end

    it 'rejects malformed and non-string versions' do
      invalid_versions.each do |version|
        expect { described_class.parse(version) }
          .to raise_error(ReleaseCeremony::Error, 'Version must use the X.Y.Z format')
      end
    end
  end

  describe '#to_s' do
    it 'returns the original version string' do
      expect(described_class.parse('12.34.56').to_s).to eq('12.34.56')
    end
  end

  describe '#tag' do
    it 'prefixes the version with v' do
      expect(described_class.parse('1.2.3').tag).to eq('v1.2.3')
    end
  end

  describe 'ordering' do
    it 'uses numeric gem version ordering' do
      versions = %w[2.0.0 1.10.0 1.9.0].map { |version| described_class.parse(version) }

      expect(versions.sort.map(&:to_s)).to eq(%w[1.9.0 1.10.0 2.0.0])
    end

    it 'does not order against other types' do
      expect(described_class.parse('1.2.3') <=> '1.2.3').to be_nil
    end
  end
end
