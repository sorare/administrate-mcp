# Contributing

Thank you for taking the time to contribute to administrate-mcp.

## Reporting a bug

Open an issue and include:

- the gem version
- the Rails and Administrate versions
- the Ruby version
- a minimal reproduction (a small dashboard and configuration, or a link to one)
- what you expected to happen and what happened instead

Do not open a public issue for a security vulnerability. See "Security issues" below.

## Proposing a change

For a small fix (a typo, a one-line bug fix, a missing test), open a pull request directly.

For anything larger, such as a new tool, a new configuration option, or a change to how
authentication or authorization works, open an issue first. Describe the problem and the change
you have in mind, so we can agree on the approach before you put time into an implementation.

## Development setup

1. Clone the repository.
2. Have a PostgreSQL server available. The test suite needs it.
3. Set the connection details if they differ from the defaults (`localhost`, port `5432`, user
   `postgres`, password `postgres`, database `administrate_mcp_test`):

   ```sh
   export ADMINISTRATE_MCP_DB_HOST=localhost
   export ADMINISTRATE_MCP_DB_PORT=5432
   export ADMINISTRATE_MCP_DB_USER=postgres
   export ADMINISTRATE_MCP_DB_PASSWORD=postgres
   export ADMINISTRATE_MCP_DB_NAME=administrate_mcp_test
   ```

4. Install the dependencies:

   ```sh
   bundle install
   ```

5. Run the test suite. `spec/spec_helper.rb` creates the test database if it does not exist yet.

   ```sh
   bundle exec rspec
   ```

6. Run the linter:

   ```sh
   bundle exec rubocop
   ```

## Pull request rules

- One logical change per pull request. Do not mix a bug fix with an unrelated refactor.
- Every behaviour change needs a test. A pull request that changes what the code does without
  changing a spec will not be merged.
- `bundle exec rubocop` must pass with no offences.
- No comments in code beyond a class's top-level description. This is the repository's
  convention: code should be self-documenting through naming and structure. An existing comment
  that explains a non-obvious constraint may stay; do not add new ones.
- Commit messages are one imperative sentence as the subject line ("Add X", not "Added X" or
  "Adds X"), followed by a body that explains why the change is needed, not only what it does.
- Do not force-push to `master`.
- Pull requests target `master`.
- Squash or rebase before merge, whichever keeps the history readable. Avoid merge commits that
  bundle in unrelated commits from `master`.

## Security issues

Do not open a public issue for a security vulnerability. See [SECURITY.md](SECURITY.md) for how
to report one.

## Design constraints

These are non-negotiable. A pull request that violates one of them will be asked to change,
whatever else it does well. See the README's "Design decisions" section for the full reasoning.

- **The engine stays host-agnostic.** It must not reference a constant belonging to a specific
  host application, at load time or at run time. Field serializers are keyed by class name
  string, not by a `case` on a class constant, so a host can register its own field classes
  without the engine knowing they exist. The admin class is read from configuration
  (`admin_class_name`), never hardcoded.
- **A recognised-but-invalid credential never falls back to the identity fallback.** If a bearer
  token matches an API key prefix or an OAuth token row, and that credential turns out to be
  revoked or expired, authentication must raise there. It must not fall through to
  `identity_fallback`, because that would let a revoked credential be laundered into an external
  identity.
- **Tool names and JSON-RPC error codes are a public contract.** Existing MCP clients depend on
  them. Do not rename a tool or change an error code without a major version bump.
- **Migrations avoid acronym-prone tokens in file names.** Zeitwerk derives constant names from
  file names, and a token like `oauth` would need a global inflection to resolve to `OAuth`
  correctly. File names such as `o_auth_access_token.rb` sidestep the problem. Follow the same
  pattern in any new migration or file that introduces such a term.
- **No foreign key on `admin_id`.** Hosts disagree about which table their admins live in, and
  some forbid cross-table constraints outright. The column stays indexed, but referential
  integrity there is the host's responsibility, not the engine's.

## Releasing

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

One-time setup, done once by a RubyGems account owner: on rubygems.org, add a trusted publisher for
this gem with repository owner `sorare`, repository `administrate-mcp`, workflow `release.yml` and
environment `rubygems`. For the very first release, when the gem name does not exist yet on
RubyGems, register it as a pending trusted publisher instead, or push the first version by hand
with `gem push` from an account with multi-factor authentication enabled.

