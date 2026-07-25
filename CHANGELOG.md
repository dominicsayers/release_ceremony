# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.1] - 2026-07-25

### Fixed

- Child commands no longer inherit the ceremony's own Bundler environment.
  Running the ceremony with `bundle exec` used to leak `RUBYOPT` and the
  `BUNDLE_*` variables into the verification commands, so a nested
  `bundle install` crashed with a `LoadError` in the `bundle` executable.
  Every command now runs in an unbundled environment when Bundler is loaded.

## [1.0.0] - 2026-07-25

### Added

- `release_ceremony prepare VERSION`: update the version file and changelog on
  the `release-vVERSION` branch and run the verification commands, without
  committing or pushing. Extracted from `url_canonicalize`'s
  `bin/release/prepare`.
- `release_ceremony publish VERSION`: validate the merged release pull
  request, tag its merge commit, watch the tag-triggered release workflow, and
  confirm the gem appears on RubyGems. Extracted from `url_canonicalize`'s
  `bin/release/publish`.
- Project auto-detection from the repository's gemspec, with optional
  overrides in `.release_ceremony.yml` (release file paths, verification
  commands, workflow file, default branch, and remote).

[Unreleased]: https://github.com/dominicsayers/release_ceremony/compare/v1.0.1...HEAD
[1.0.1]: https://github.com/dominicsayers/release_ceremony/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/dominicsayers/release_ceremony/compare/v0.0.0...v1.0.0
