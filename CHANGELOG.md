# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html). While the major version is 0, a
minor release may change behaviour a host depends on; the entry says so when it does.

## [Unreleased]

## [0.2.0] - 2026-09-22

### Added

- `config.admin_foreign_key`, defaulting to `:admin_id`, so a host whose admin table already has a
  differently named foreign key can keep that column name instead of renaming it. The association
  stays called `admin` everywhere in the engine's API; only the column it reads and writes changes.
- `config.persist_feedback`, defaulting to `false`, so a host can use `report_mcp_improvement` and
  `on_feedback` as a plain signal without carrying the `administrate_mcp_feedbacks` table, its model
  or its migration. Set it to `true` for the previous behaviour: the report is persisted before
  `on_feedback` runs, and the dashboard and `CleanOldFeedbacks` housekeeping become meaningful.
- `config.feedback_tool`, defaulting to `true`, to stop publishing `report_mcp_improvement`
  altogether.

### Changed

- `on_feedback` is now called with a `FeedbackReport`, a plain value object, instead of a persisted
  `Feedback` record. A host reading attributes off the argument (`category`, `suggestion`,
  `resource_name`, `admin`, `api_key`) sees no difference; a host that relied on it being an
  `ActiveRecord` instance, for example calling `.save`, `.update` or `.reload` on it, or expecting
  `.persisted?` to be true, must update its `on_feedback` hook. When `config.persist_feedback` is
  `true` the persisted record is still reachable, as `report.record`.

## [0.1.0] - 2026-09-22

### Added

- Rails engine exposing Administrate dashboards over the Model Context Protocol.
- Three generic tools built from a host's dashboards: `admin_resource_list_resources`,
  `admin_resource_list`, `admin_resource_show`.
- `report_mcp_improvement`, a feedback tool so users can report what the server got wrong, stored
  through `Administrate::MCP::Feedback` and cleaned up with `CleanOldFeedbacks`.
- Two optional Sidekiq tools, `sidekiq_stats` and `sidekiq_retries`, backed by a host-supplied
  `sidekiq_stats_provider`.
- `mcp_action`, a dashboard macro that publishes a host-declared write action as its own tool.
- API key authentication: tokens are generated with a configurable prefix
  (`api_key_token_prefix`), stored only as a SHA-256 digest, and default to read-only unless
  granted write access.
- A complete OAuth 2.1 authorization server: Dynamic Client Registration, a consent screen, PKCE,
  refresh tokens, and the discovery documents clients need to find all of it. Access tokens last a
  week, authorization codes ten minutes, and refreshing revokes the old token.
- `config.oauth = false` to turn the built-in OAuth server off for hosts where something in front
  of the application, such as Cloudflare Access managed OAuth, already runs one.
- `config.identity_fallback`, an extension point consulted only when no credential the engine
  issued matches, for hosts that authenticate the caller before the request reaches Rails.
- `Administrate::MCP::CloudflareAccess`, a verifier for the assertion Cloudflare Access attaches to
  a request, ready to use as an `identity_fallback`.
- `config.admin_active`, checked on every authenticated call, so a host can revoke every credential
  an admin holds by deactivating the admin in one place.
- Two authorization adapters, `Authorization::Permissive` and `Authorization::Pundit`, plus
  per-tool role gating through `requires_roles` and `config.default_required_roles`.
- `FastSearch`, a subclass of `Administrate::Search` that searches exactly by default, with `*` as
  the only wildcard, and casts every compared column to text so a plain word searched against a
  uuid column returns no rows instead of raising.
- Dashboard-level MCP declarations: `MCP_BASE_SCOPE`, `MCP_SKIPPED_ATTRIBUTES`, `mcp_value` on a
  field, and collection filters.
- `Administrate::MCP::RackAttack.throttles`, a set of recommended Rack::Attack throttles for the
  OAuth endpoints, for hosts that already depend on rack-attack.
- Migrations for `administrate_mcp_api_keys`, `administrate_mcp_feedbacks`,
  `administrate_mcp_oauth_applications`, `administrate_mcp_oauth_access_grants` and
  `administrate_mcp_oauth_access_tokens`, all using uuid primary keys, an indexed but
  unconstrained uuid `admin_id`, and array columns for `redirect_uris` and `grant_types`.

### Security

- OAuth access tokens, refresh tokens and authorization codes are now stored as SHA-256 digests
  (`token_digest`, `refresh_token_digest`) instead of plaintext, matching how API keys were already
  stored. The plaintext is handed to the caller once, when it is issued, and is not recoverable
  afterwards. This changes the schema of the authorization tables migration, so installations that
  took the gem from git before 0.1.0 must reinstall its migrations rather than migrate
  incrementally.

[Unreleased]: https://github.com/sorare/administrate-mcp/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/sorare/administrate-mcp/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/sorare/administrate-mcp/releases/tag/v0.1.0
