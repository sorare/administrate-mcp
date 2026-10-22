# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html). While the major version is 0, a
minor release may change behaviour a host depends on; the entry says so when it does.

## [Unreleased]

### Added

- An `mcp_action` block can send data back to the client. It returns
  `Administrate::MCP::Result.success(record:, data:)`, or any result object answering `mcp_data`,
  and the response gains a `data` key next to `status`, `model`, `id` and `action`, which are
  unchanged. The record, optional, goes through the same checks as a record returned directly, so
  an unsaved or invalid one is still an error and a collection action still answers its `id`.
  `Result.failure(message, data:)` is an error whose first content block is the message, as before,
  followed by a second one carrying `{ "error": message, "data": … }` as JSON when there is data.
  The data must be a Hash of plain JSON values and its JSON at most `config.action_data_max_bytes`
  (new, 32 KB by default, `nil` for no limit); anything else is answered as an error naming the
  offending path and saying the action ran. A plain Hash returned by a block is still not sent
  back. See [Returning data from an action](docs/dashboards.md#returning-data-from-an-action).

### Changed

- A tool error may now carry a second content block. Clients that read only the first block still
  get the message on its own; only failures that return data, through `Result.failure` or a result
  answering `mcp_data`, add the second block.

## [0.4.0] - 2026-10-21

### Added

- Collection-level write actions: `mcp_action name, on: :collection, ...` publishes a tool with no
  `id` in its input schema. Nothing is loaded; the block receives `admin:` and `params:`, and the
  authorization predicate, `<name>?` by default as for member actions and overridable with
  `predicate:` or `pundit:`, is checked against a new instance of the model through
  `config.authorization`, when the tool list is built and on every call. The `write` scope gate,
  the `on_tool_call` audit and the error reporting work as for member actions, and the tool keeps
  the `<resource>_<action>` name. When the block returns an Active Record object, the response
  includes its primary key as `id`. `on: :member` stays the default.
- Presigned uploads for Shrine attachments, off until `config.uploads.enabled` is set. The
  `uploads_prepare` tool takes the target action's `tool` name, an `attribute` and `files`, an
  object of filename to size in bytes. It is only published to, and only answers, a caller
  authorized for an action that accepts uploads for that attribute. It records an
  `administrate_mcp_upload_batches` row and returns `{ filename => { upload_id, method, url,
  fields } }`, one presigned `POST` per file whose policy bounds the content length. An
  `mcp_action` declared with `uploads:` (`true`, a list of attributes, or per-attribute
  `content_types:` and `max_size:`) takes an optional `<attribute>_upload_id` for each attachment
  attribute; the engine resolves it and the block receives the file as `params[:<attribute>]`.
  Resolving checks the owning admin (another admin's id is not found), the action and attribute
  the upload was prepared for, the batch expiry, that the file was uploaded, and its real size
  and content type, on a copy under a key no URL points to; the copy is reused if the same id is
  passed again. Defaults: png, jpeg and webp, 10 MB, 10 files per call, 15-minute URLs, 1-hour
  batches. `Administrate::MCP::CleanExpiredUploadBatches` deletes expired batches. The default
  storage is the Shrine `:cache` storage, replaceable through `config.uploads.storage`; the gem
  gains no dependency. Hosts that enable uploads need the new migration
  (`bin/rails administrate_mcp:install:migrations`).

### Changed

- **Behaviour change for hosts:** an `mcp_action` block that returns an Active Record object that
  was never saved or has errors is now reported as an error, with the record's validation messages,
  instead of `status: ok`. A record the block destroyed is still a success. A block that returns
  `false`, as `record.update(...)` does on a validation error and `record.destroy` does when a
  callback aborts it, is now an error too, with the loaded record's validation messages for a member
  action when it has any. A block that returned `false` to mean success must return something else.

## [0.3.1] - 2026-10-20

### Security

- A `tools/call` argument named `admin` no longer replaces the authenticated admin passed to a
  tool's `execute` and to `mcp_action` blocks
  ([GHSA-vv7c-hhjc-fhq8](https://github.com/sorare/administrate-mcp/security/advisories/GHSA-vv7c-hhjc-fhq8)).
  The call is now refused with a tool error. For built-in and host-defined tools, the refusal comes
  after the scope and role checks, and the `on_tool_call` hook still reports the call under the
  authenticated admin, with the refused argument in `arguments`. The tools generated from
  `mcp_action` refuse it while validating arguments, before the hook runs.

### Changed

- **Behaviour change for hosts:** a tool that declares an input property named `admin` now raises
  `ArgumentError` when its class is loaded, and an `mcp_action` param named `admin` or `id` raises
  `ArgumentError` when the dashboard is loaded. Rename the property or param.
- **Behaviour change for clients:** the tools generated from `mcp_action` declarations now reject
  arguments they do not declare, with an `Invalid arguments` tool error, instead of passing them to
  the block in `params`.

## [0.3.0] - 2026-10-02

### Changed

- **Behaviour change for clients:** two failures of `admin_resource_list_resources`,
  `admin_resource_list` and `admin_resource_show` now return HTTP 200 with a tool error
  (`result.isError: true`) instead of HTTP 403 with `X-Auth-Error: forbidden` and JSON-RPC code
  -32003. Clients such as Claude showed that 403 as an authentication failure and dropped the message:
  - An unknown resource name. The message says the name is not registered and lists up to five
    close registered names, taken only from the resources the caller can read.
  - A registered resource the caller may not read. The message is "Resource `<name>` exists but you
    are not authorized to list it" (or "show it"), followed by the authorization adapter's own
    message when the host wrote one. The old 403 body already told the two cases apart
    (`Unknown resource: …` against `Not authorized to show? <Model>`); the difference is that
    clients now display it.

  A tool-level refusal, a missing OAuth scope or a required role, is still a 403 for now
  ([#11](https://github.com/sorare/administrate-mcp/issues/11)). The per-resource denial is raised
  as `Administrate::MCP::ResourceForbiddenError`, a subclass of `UnauthorizedError`, so host code
  that rescues `UnauthorizedError` still catches it.

### Fixed

- A `subscriptions/listen` request no longer raises `NoMethodError` in the host's Rack stack. The
  `mcp` gem answers it with a streaming SSE body meant to stay open, which the engine's controller
  cannot serve; the transport is now built with `serve_subscriptions_listen: false`, so the method
  is answered with HTTP 404 and JSON-RPC error `-32601` like any unimplemented method, and
  `server/discover` stops advertising the `listChanged` and `subscribe` capability flags.

## [0.2.0] - 2026-09-22

### Added

- The admin console for the engine's own tables: the `Administrate::MCP::ApiKeyDashboard` and
  `Administrate::MCP::FeedbackDashboard` base dashboards, and the `Administrate::MCP::ApiKeysAdmin`
  and `Administrate::MCP::FeedbacksAdmin` controller concerns. A host subclasses each dashboard
  under the name its own inflections give `administrate_mcp_api_key_dashboard.rb`, which differs
  between an application that registers MCP as an acronym and one that does not. The concern goes in
  a controller of the host's own, which keeps its base controller, authentication and policies; the
  engine supplies the resource wiring, key generation, the one-time plaintext in the flash, and
  revocation. Write-enabled keys are refused until the host overrides `mcp_write_access_allowed?`.
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

[Unreleased]: https://github.com/sorare/administrate-mcp/compare/v0.4.0...HEAD
[0.4.0]: https://github.com/sorare/administrate-mcp/compare/v0.3.1...v0.4.0
[0.3.1]: https://github.com/sorare/administrate-mcp/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/sorare/administrate-mcp/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/sorare/administrate-mcp/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/sorare/administrate-mcp/releases/tag/v0.1.0
