# AGENTS.md

Guidance for coding agents working in this repository.

## What this repository is

`administrate-mcp` is a public, open-source Ruby gem (MIT, published on RubyGems) that exposes a
Rails application's Administrate dashboards over the Model Context Protocol. It is a Rails engine.
Anyone can read this repository, its issues, its pull requests and their full edit history.

You work here as a maintainer of the gem. Make the decisions a maintainer would make for the gem
and all of its users, not for one application that happens to use it:

- Fix a problem at the level of the engine, so every host gets the fix. Do not add a special case
  for one host's setup.
- Describe bugs and changes in terms of the gem's own behaviour, for example "a
  `subscriptions/listen` request raises `NoMethodError` in the host's Rack stack", not in terms of
  one application that reported it.
- Treat tool names, JSON-RPC error codes, configuration options and documented behaviour as a
  public contract. Other people's applications and MCP clients depend on them.
- Follow Semantic Versioning. While the major version is 0, a minor release may change behaviour a
  host depends on, and its CHANGELOG entry must say so.
- Work to be done in an application that uses the gem, such as bumping its gem pin, is separate
  from work in this repository. Do not do it here.

## No internal references

This repository is public. Nothing internal to the organisations that use the gem may appear in
anything that ends up in it: code, specs, docs, CHANGELOG, commit messages, branch names, pull
request titles and descriptions, issues, or review comments. That includes:

- names of private applications or services that use the gem
- internal hostnames and URLs
- links to or IDs from error trackers, observability tools, ticket trackers or chat (for example
  Sentry issue IDs, Datadog links, Linear or Jira tickets, Slack threads)
- stack traces or logs copied from a private application, unless they are rewritten to show only
  the gem's and its public dependencies' frames
- customer or user data

When a task arrives with internal context, such as an error-tracker issue from a host application,
keep that context in the conversation. In the public record, reproduce the problem with the gem and
its dummy app and describe it in those terms.

A pull request description on GitHub keeps its edit history, and a force-pushed commit stays
reachable by its SHA. Removing something after publishing it does not fully remove it, so check the
text before you push or post it.

## Remotes

- `github` (`git@github.com:sorare/administrate-mcp.git`) is the canonical, public repository.
  Pull requests are opened there, against `master`, and releases are tagged there.
- `origin` may point to a GitLab mirror. Its `master` can hold the same history under different
  SHAs. Base new branches on `github/master`, and push them to `github`.

## Development

The test suite needs a reachable PostgreSQL server. The spec helper creates the database on first
run. Connection settings come from `ADMINISTRATE_MCP_DB_HOST`, `_PORT`, `_USER`, `_PASSWORD` and
`_NAME` (defaults: `localhost`, `5432`, `postgres`, `postgres`, `administrate_mcp_test`).

```sh
bundle install
bundle exec rspec
bundle exec rubocop
```

Both must pass before a change is pushed. CI runs the same two commands.

`spec/dummy` is a small host application used by the specs. It has an `Admin`, a `Widget` and a
`Gadget`; see [docs/development.md](docs/development.md).

When a change depends on how the `mcp` gem behaves, read that gem's source for the version in
`Gemfile.lock`, and check the oldest version the gemspec allows (`~> 1.5`) when it matters.

## Conventions

[CONTRIBUTING.md](CONTRIBUTING.md) is the source of truth. The rules agents most often need:

- One logical change per pull request.
- Every behaviour change needs a spec. Write it first and confirm it fails without the change.
- No new code comments beyond a class's top-level description. An existing comment that explains a
  non-obvious constraint may stay.
- Commit subject: one imperative sentence ("Add X"). The body explains why the change is needed.
- Add an entry under `## [Unreleased]` in [CHANGELOG.md](CHANGELOG.md), in the Keep a Changelog
  section that fits (Added, Changed, Fixed, ...). Call out behaviour changes a host or client depends
  on.
- Do not bump `Administrate::MCP::VERSION` in a feature or fix pull request. A release is its own
  `Release vX.Y.Z` pull request; see [RELEASING.md](RELEASING.md).
- The design constraints in CONTRIBUTING.md are non-negotiable. In short: the engine never
  references a host's constants, a recognised but invalid credential never falls back to
  `identity_fallback`, routes are Rack lambdas, file names avoid acronym-prone tokens, there is no
  foreign key on the admin column, and the only inflection (`mcp` to `MCP`) is registered on the
  engine's own autoloader.

## Security

Report or discuss vulnerabilities as [SECURITY.md](SECURITY.md) describes, never in a public issue
or pull request.
