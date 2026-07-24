# frozen_string_literal: true

module ReleaseCeremony
  # Transforms a Keep a Changelog file for a release: the Unreleased notes
  # move under a new dated heading and the comparison links are rewritten.
  class Changelog
    UNRELEASED_HEADING = /^## \[Unreleased\][ \t]*$/
    VERSION_HEADING = /^## \[[^\]]+\].*$/
    REFERENCE_DEFINITION = /^\[[^\]]+\]:[ \t]+.*$/
    ANY_UNRELEASED_LINK = /^\[Unreleased\]:.*$/

    def initialize(contents:, current_version:, version:, today:, compare_base:, changelog_file:)
      @contents = contents
      @current_version = current_version
      @version = version
      @today = today
      @compare_base = compare_base
      @changelog_file = changelog_file
    end

    def transform
      heading = unreleased_heading
      ensure_unreleased_notes!(heading)
      ensure_requested_version_absent!
      link = unreleased_link
      ensure_previous_version_matches!(link)

      insert_release_heading(heading).sub(link[0], replacement_links)
    end

    private

    attr_reader :changelog_file, :compare_base, :contents, :current_version, :today, :version

    def unreleased_link_pattern
      /^\[Unreleased\]: #{Regexp.escape(compare_base)}v(?<previous>\d+\.\d+\.\d+)\.\.\.HEAD[ \t]*$/
    end

    def unreleased_heading
      headings = contents.to_enum(:scan, UNRELEASED_HEADING).map { Regexp.last_match.dup }
      raise Error, "#{changelog_file} must contain exactly one Unreleased heading" unless headings.one?

      headings.first
    end

    def ensure_unreleased_notes!(heading)
      following_text = contents[heading.end(0)..]
      boundary = [VERSION_HEADING, REFERENCE_DEFINITION]
                 .filter_map { |pattern| following_text.match(pattern) }
                 .min_by { |match| match.begin(0) }
      notes = boundary ? following_text[0...boundary.begin(0)] : following_text
      raise Error, "#{changelog_file} Unreleased section has no notes" if notes.strip.empty?
    end

    def ensure_requested_version_absent!
      heading_pattern = /^## \[#{Regexp.escape(version.to_s)}\].*$/
      link_pattern = /^\[#{Regexp.escape(version.to_s)}\]:.*$/
      raise Error, "#{changelog_file} heading for #{version} already exists" if contents.match?(heading_pattern)
      raise Error, "#{changelog_file} comparison link for #{version} already exists" if contents.match?(link_pattern)
    end

    def unreleased_link
      pattern = unreleased_link_pattern
      candidates = contents.to_enum(:scan, ANY_UNRELEASED_LINK).map { Regexp.last_match.dup }
      valid = candidates.select { |candidate| pattern.match?(candidate[0]) }
      unless candidates.one? && valid.one?
        raise Error, "#{changelog_file} must contain exactly one Unreleased comparison link"
      end

      pattern.match(valid.first[0])
    end

    def ensure_previous_version_matches!(link)
      return if link[:previous] == current_version.to_s

      raise Error,
            "#{changelog_file} Unreleased link compares from v#{link[:previous]}, but VERSION is #{current_version}"
    end

    def insert_release_heading(heading)
      release_heading = "#{heading[0]}\n\n## [#{version}] - #{today.strftime('%Y-%m-%d')}"
      contents.sub(heading[0], release_heading)
    end

    def replacement_links
      unreleased = "[Unreleased]: #{compare_base}v#{version}...HEAD"
      release = "[#{version}]: #{compare_base}v#{current_version}...v#{version}"
      "#{unreleased}\n#{release}"
    end
  end
end
