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
VERSION=1.2.3

git switch -c "release-v$VERSION"
release_ceremony prepare "$VERSION"
# inspect the changes, then commit and push the branch
# open the pull request and merge it
release_ceremony publish "$VERSION"
```

Publication itself happens in CI: the pushed tag triggers your release
workflow, which should publish to RubyGems (see
[Setting up Trusted Publishing](#setting-up-trusted-publishing)). `publish`
only tags, watches, and verifies.

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

## Setting up Trusted Publishing

`publish` never pushes to RubyGems itself; the tag-triggered workflow does,
ideally with [Trusted Publishing](https://guides.rubygems.org/trusted-publishing/)
and the [`rubygems/release-gem`](https://github.com/rubygems/release-gem)
action, so that no API key exists to be stored or leaked. One-time setup:

- **Existing gem**: on rubygems.org, open the gem → Trusted publishers →
  Create, and enter the repository owner and name, the workflow filename
  (e.g. `release.yml`), and the environment name the workflow declares
  (e.g. `release`).
- **New gem**: nothing is created on RubyGems manually. Instead, register a
  [pending trusted publisher](https://rubygems.org/profile/oidc/pending_trusted_publishers)
  (Profile → OIDC → Pending trusted publishers) with the same fields plus the
  gem's name. The first successful push from the workflow creates the gem,
  converts the pending publisher into a normal one, and makes you the owner.
  Pending publishers expire 12 hours after creation, so register on the day
  of the first release; if it lapses, just register it again.
- **GitHub environment**: if the workflow's publish job declares
  `environment: release`, create that environment in the repository settings
  (Settings → Environments). Trusted Publishing only accepts tokens minted
  from the registered environment, and you can attach protection rules such
  as required reviewers to it.

RubyGems also ships a CLI that automates the RubyGems side:
[`gem exec configure_trusted_publisher`](https://github.com/rubygems/configure_trusted_publisher).

## Re-running publish

`publish` converges when reality matches expectations and stops loudly when
it doesn't, so after most failures you can simply run it again:

- Everything before the confirmation prompt is read-only validation; a
  failure there has changed nothing.
- Tagging is guarded: if the remote tag already exists at the merge commit,
  tagging and pushing are skipped; if only a local tag exists, it is pushed
  as-is. A tag that exists anywhere but points to the wrong commit aborts the
  ceremony before the prompt — `publish` never moves or deletes a tag.
- Watching the workflow and checking RubyGems are read-only, so a run that
  died mid-watch or hit RubyGems index lag re-attaches to the completed
  workflow run and re-verifies. Re-running after a fully successful publish
  succeeds again without side effects.

The exception is a failed release workflow. Re-running `publish` does not
retry it: the tag is already on the remote, so nothing re-pushes, no new
workflow is triggered, and watching the same failed run fails again. Re-run
the workflow first, then re-run `publish` to watch and verify it:

```sh
gh run rerun <run-id> --failed
release_ceremony publish "$VERSION"
```

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

## Comparison with create_github_release

[`create_github_release`](https://github.com/main-branch/create_github_release)
automates the same job — releasing a gem hosted on GitHub through a release
branch and pull request — but makes the opposite choice at almost every step:

| | `release_ceremony` | `create_github_release` |
| --- | --- | --- |
| Committing and pushing | You commit, push, and open the PR yourself | One command commits, tags, pushes, and opens the PR |
| Tag timing | Tags the merge commit after the PR merges, validating it first | Tags the release branch before merging, requiring a manual fast-forward merge |
| Changelog | Promotes your curated Keep a Changelog `Unreleased` notes | Generates release notes from the commit list |
| Verification | Runs configurable verification commands during `prepare` | None |
| Publishing | Tag-triggered CI publishes; `publish` watches the workflow and confirms the version on RubyGems | Manual `rake release:rubygem_push` from your machine |
| Version | Explicit `X.Y.Z` only | Computes major/minor/patch bumps, supports pre-releases |
| GitHub release object | Not created | Created |

Choose `create_github_release` if you want the release automated away in one
command. Choose `release_ceremony` if you want curated release notes, a
human inspecting and merging the release pull request, publication only from
CI, and verification at every step.

## Development

```sh
mise install
bundle install
bundle exec rspec    # tests
bundle exec rubocop  # static code analysis
```

## License

[MIT](LICENSE)
