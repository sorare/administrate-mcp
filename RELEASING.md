# Releasing

For maintainers. Contributors do not need this; see [CONTRIBUTING.md](CONTRIBUTING.md).

Releases are published to RubyGems by the `Release` workflow when a tag matching `v*` is pushed.
The workflow authenticates with RubyGems trusted publishing (OpenID Connect), so no API key is
stored in this repository.

To cut a release:

1. Bump `Administrate::MCP::VERSION` in `lib/administrate/mcp/version.rb`.
2. In `CHANGELOG.md`, rename the `Unreleased` section to the new version with today's date and add a
   fresh empty `Unreleased` section above it.
3. Commit as `Release vX.Y.Z` and open a pull request; merge it once CI is green.
4. Tag the merge commit `vX.Y.Z` and push the tag. The workflow checks that the tag matches the
   version file, builds the gem and pushes it.

One-time setup, done once by a RubyGems account owner. Because the gem does not exist on RubyGems
yet, the first registration is a pending trusted publisher, created from the RubyGems profile rather
than from a gem page, at https://rubygems.org/profile/oidc/pending_trusted_publishers. Its fields are:

| Field | Value |
| --- | --- |
| RubyGem name | `administrate-mcp` |
| Repository owner | `sorare` |
| Repository name | `administrate-mcp` |
| Workflow filename | `release.yml` |
| Environment | `release` |

The environment has to match the `environment:` in `.github/workflows/release.yml` exactly. Create it
in the repository under Settings, Environments, so you can add a required reviewer and limit who can
publish. After the first release the same entry appears on the gem's own trusted publishers page.

If the pending registration is not available, the fallback is to push the first version by hand with
`gem build` and `gem push` from an account with multi-factor authentication enabled, then register
the trusted publisher on the gem page for later releases.
