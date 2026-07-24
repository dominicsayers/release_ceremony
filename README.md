# release_ceremony

A strict, verified release ceremony for RubyGems projects hosted on GitHub.

`release_ceremony` provides two commands:

- **`release_ceremony prepare VERSION`** — on the `release-vVERSION` branch,
  updates the version file, moves the changelog's Unreleased notes under a
  dated release heading, rewrites the comparison links, and runs the
  verification commands. It never commits or pushes.
- **`release_ceremony publish VERSION`** — after the release pull request has
  merged, validates the merge commit, tags it `vVERSION`, pushes the tag,
  watches the tag-triggered GitHub Actions release workflow, and confirms the
  new version appears on RubyGems.

Both commands validate aggressively and fail loudly: every transformation is
exact-match, file writes are transactional, and nothing is tagged or pushed
until you type the confirmation phrase.

## The ceremony

```sh
git switch -c release-v1.2.3
release_ceremony prepare 1.2.3
# inspect the changes, then commit and push the branch
# open the pull request and merge it
release_ceremony publish 1.2.3
```

Publication itself happens in CI: the pushed tag triggers your release
workflow, which should publish to RubyGems (for example with
[Trusted Publishing](https://guides.rubygems.org/trusted-publishing/) and the
`rubygems/release-gem` action). `publish` only tags, watches, and verifies.

## Installation

Add the gem to your Gemfile:

```ruby
group :build do
  gem 'release_ceremony', require: false
end
```

## What it assumes

- The gem's version lives in `lib/<gem_name>/version.rb` as exactly one
  single-quoted `VERSION = 'X.Y.Z'` assignment.
- `CHANGELOG.md` follows [Keep a Changelog](https://keepachangelog.com/):
  exactly one `## [Unreleased]` heading with notes, dated release headings,
  and reference-style comparison links at the bottom.
- Versions are strict `X.Y.Z` semantic versions (no prereleases), tagged
  `vX.Y.Z`.
- Release work happens on a branch named `release-vX.Y.Z`, merged to `main`
  on the `origin` remote via exactly one pull request.
- The repository is on GitHub, with the `gh` CLI installed and authenticated,
  and has a `release.yml` workflow triggered by pushing the tag.

The gem name and repository URL are read from the repository's gemspec
(`metadata['source_code_uri']`, falling back to `homepage`). Everything else
above is a convention that `.release_ceremony.yml` can override.

## Configuration

Create `.release_ceremony.yml` in the repository root to override any of the
defaults:

```yaml
gem_name: my_gem                    # default: the gemspec's name
repo_url: https://github.com/acme/my_gem # default: the gemspec's source_code_uri or homepage
version_file: lib/my_gem/version.rb # default: lib/<gem_name>/version.rb
changelog_file: CHANGELOG.md        # default: CHANGELOG.md
workflow_file: release.yml          # default: release.yml
default_branch: main                # default: main
remote: origin                      # default: origin
verification_commands:              # default: the four commands below
  - bundle install
  - bundle exec rspec
  - bundle exec rubocop
  - bundle exec rake build
```

`verification_commands` are split shell-style into words and run directly
(no shell), in order, from the repository root. A project that manages its
toolchain with [mise](https://mise.jdx.dev/), for example, would use
`mise exec -- bundle exec rspec`.

## Development

```sh
mise install
bundle install
bundle exec rspec    # tests
bundle exec rubocop  # static code analysis
```

## License

[MIT](LICENSE)
