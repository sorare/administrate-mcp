# administrate-mcp

A Rails engine that exposes [Administrate](https://github.com/thoughtbot/administrate) dashboards
over the [Model Context Protocol](https://modelcontextprotocol.io), so an MCP client such as Claude
can list, show and search your admin data, and run the write actions you opt in, with the same
permissions the admin UI enforces.

[![Gem Version](https://img.shields.io/gem/v/administrate-mcp.svg)](https://rubygems.org/gems/administrate-mcp)
[![CI](https://github.com/sorare/administrate-mcp/actions/workflows/ci.yml/badge.svg)](https://github.com/sorare/administrate-mcp/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE.txt)
[![Ruby](https://img.shields.io/badge/ruby-%3E%3D%203.2-CC342D.svg)](administrate-mcp.gemspec)

## Table of contents

- [Why](#why)
- [Features](#features)
- [Demo](#demo)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quick start](#quick-start)
- [Configuration](#configuration)
- [Routes](#routes)
- [Dashboard declarations](#dashboard-declarations)
- [Authentication](#authentication)
- [OAuth](#oauth)
- [Rate limiting](#rate-limiting)
- [Admin integration](#admin-integration)
- [Development](#development)
- [Security](#security)
- [Contributing](#contributing)
- [Changelog](#changelog)
- [Licence](#licence)

## Why

Administrate dashboards are built for a person clicking through a browser. This gem reads the same
dashboard declarations, the same Pundit policies and the same scoped queries, and publishes them as
MCP tools, so an LLM client can answer questions about your admin data and, where you allow it, act
on it, without a second implementation of your authorization rules. Nothing in the engine knows
about your application; everything host-specific goes through `Administrate::MCP.configure`.

## Features

- Three generic tools built from every Administrate dashboard: `admin_resource_list_resources`,
  `admin_resource_list`, `admin_resource_show`.
- Write actions declared per dashboard with `mcp_action`, each published as its own tool, gated by
  the `write` scope (an API key with write access, or an OAuth token granted it) and the resource's own authorization predicate on the loaded record.
- Three ways to authenticate a caller: API keys stored as a digest, an external identity provider
  through `identity_fallback` (a Cloudflare Access verifier ships with the gem), and an optional
  built-in OAuth 2.1 server with Dynamic Client Registration, PKCE and refresh tokens, on by default
  and disabled with one setting.
- Pundit-aware authorization by default: reads run through the same `index?` and `show?` predicates
  as the admin UI, so a resource an admin cannot see in the browser is not exposed over MCP either.
- Search, filters and field selection built from the dashboard's own declarations, plus foreign key
  filters that need no declaration at all.
- A feedback tool, `report_mcp_improvement`, so users can report what the server got wrong. The
  signal is always available through `config.on_feedback`; storing it, the dashboard and the
  clean-up service are a batteries-included option a host turns on with `config.persist_feedback`.
- Optional Sidekiq introspection tools, `sidekiq_stats` and `sidekiq_retries`, wired to a stats
  provider object you supply.
- No reference to a constant it does not own: field serializers are keyed on class names, dashboards
  opt in per attribute, and every host-specific behaviour is configuration, not a subclass.

## Demo

A `tools/list` call against the JSON-RPC endpoint, authenticated with an API key:

```sh
curl https://admin-mcp.example.com/ \
  -H 'Authorization: Bearer amcp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx' \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc": "2.0", "method": "tools/list", "id": 1}'
```

returns the generic tools built from your dashboards, plus any `mcp_action` you declared, among
them:

```json
{
  "result": {
    "tools": [
      { "name": "admin_resource_list_resources" },
      { "name": "admin_resource_list" },
      { "name": "admin_resource_show" },
      { "name": "report_mcp_improvement" }
    ]
  }
}
```

A `tools/call` against `admin_resource_list`, restricted to three fields:

```json
{
  "jsonrpc": "2.0",
  "method": "tools/call",
  "id": 2,
  "params": {
    "name": "admin_resource_list",
    "arguments": { "resource": "widget", "fields": ["id", "name", "status"] }
  }
}
```

returns columns, rows and pagination metadata built from the dashboard's `COLLECTION_ATTRIBUTES`:

```json
{
  "columns": ["url", "id", "name", "status"],
  "rows": [
    [
      "https://admin.example.com/admin/widgets/1",
      "1",
      "Turbo encabulator",
      "published"
    ],
    [
      "https://admin.example.com/admin/widgets/2",
      "2",
      "Flux capacitor",
      "draft"
    ]
  ],
  "meta": { "page": 1, "per_page": 10, "total_count": 2, "total_pages": 1 }
}
```

## Requirements

- Ruby 3.2 or newer.
- Rails 8.1 or newer.
- Administrate 1.0.0.beta3 or newer, below 2.0 (the search implementation calls methods
  `Administrate::Search` treats as internal, see [Search](docs/dashboards.md#search)).
- PostgreSQL. The migrations create uuid primary keys defaulted with `gen_random_uuid()` and store
  the OAuth `redirect_uris` and `grant_types` as array columns.

## Installation

```ruby
# Gemfile
gem 'administrate-mcp'
```

Copy the migrations and run them:

```sh
bundle install
bin/rails administrate_mcp:install:migrations
bin/rails db:migrate
```

The tables are `administrate_mcp_api_keys`, `administrate_mcp_feedbacks`,
`administrate_mcp_oauth_applications`, `administrate_mcp_oauth_access_grants` and
`administrate_mcp_oauth_access_tokens`. They use uuid primary keys and a uuid column, `admin_id` by
default, that is indexed but carries no foreign key constraint, so the engine works with any admin
table. Set `config.admin_foreign_key` before running the migrations if the host's own admin table
already uses a different column name and renaming it is not an option, for example a live
credentials table.

`administrate_mcp_feedbacks` is only needed when `config.persist_feedback` is `true`; leave it
`false`, the default, and the migration ships but the table is never read from or written to.

## Quick start

The smallest configuration that works. Save it as `config/initializers/administrate_mcp.rb`; it
must run before the engine's models load, because the `admin` association reads `admin_class_name`
and `admin_foreign_key`:

```ruby
Administrate::MCP.configure do |c|
  c.admin_class_name = 'Administrator'
  c.current_admin = ->(controller) { controller.send(:warden)&.authenticate(scope: :administrator) }
  c.issuer = 'https://admin-mcp.example.com'
  c.admin_origin = 'https://admin.example.com'
end
```

Then draw the routes, split across the MCP origin and the admin origin (see [Routes](#routes) for
why):

```ruby
# config/routes.rb
Rails.application.routes.draw do
  constraints ->(request) { request.subdomain == 'admin-mcp' } do
    Administrate::MCP::Routes.draw_mcp_origin(self)
  end

  constraints subdomain: 'admin' do
    Administrate::MCP::Routes.draw_admin_origin(self)
  end
end
```

This draws a full OAuth 2.1 server by default (see [OAuth](#oauth) to turn it off) and grants every
authenticated admin access to every dashboard until you set `c.authorization`. For the full picture,
including hooks, authorization adapters, field serializers and identity fallback, see the reference
sections below.

## Configuration

The full `Configuration` object, the settings table, the authorization adapters, and how to
register, skip or reclassify a field class: [docs/configuration.md](docs/configuration.md).

## Routes

Why the consent screen and the JSON-RPC endpoint are drawn on separate origins, and what each route
helper adds: [docs/routes.md](docs/routes.md).

## Dashboard declarations

`MCP_DESCRIPTION`, `MCP_BASE_SCOPE`, `MCP_SKIPPED_ATTRIBUTES`, `MCP_EXPOSED`, `COLLECTION_FILTERS`
and `mcp_action`, the constants and macro that turn one dashboard into an MCP resource with its own
readable fields and writable actions: [docs/dashboards.md](docs/dashboards.md).

## Authentication

How a request is authenticated (API key, then OAuth token, then `identity_fallback`), how to issue
and rotate API keys, and the `identity_fallback` recipe for an identity resolved in front of the
application: [docs/authentication.md](docs/authentication.md). A Cloudflare Access verifier ships
with the gem for hosts that run edge-managed OAuth in front of the application:
[docs/authentication.md#identity-fallback](docs/authentication.md#identity-fallback).

## OAuth

The built-in OAuth 2.1 server, what turning it off with `c.oauth = false` changes, and when a host
should: [docs/oauth.md](docs/oauth.md).

## Rate limiting

The rack-attack throttles recommended for the OAuth endpoints, and the helper that registers them
for you: [docs/oauth.md#rate-limiting](docs/oauth.md#rate-limiting).

## Admin integration

Exposing the engine's own tables (API keys, feedback) in your host admin, customising the consent
screen, and cleaning up old feedback: [docs/admin-integration.md](docs/admin-integration.md).

## Development

```sh
bundle install
bundle exec rspec
bundle exec rubocop
```

Needs a reachable PostgreSQL server; the test suite creates its own database on first run. See
[docs/development.md](docs/development.md) for the dummy application and the Postgres environment
variables.

## Security

See [SECURITY.md](SECURITY.md) for how to report a vulnerability.

The JSON-RPC endpoint authenticates by bearer token only. It never falls back to a session cookie,
so a browser signed into the admin UI cannot drive the protocol endpoint. API keys, OAuth access and
refresh tokens, and OAuth authorization codes are all stored as SHA-256 digests, never in plaintext.
The Cloudflare Access verifier fails closed: a blank team domain or audience makes it refuse every
request rather than admit an unverified one. A credential does not outlive the admin who holds it,
because `admin_active` is checked on every call, whether the credential is an API key, an OAuth
token, or an identity resolved through `identity_fallback`.

## Contributing

Bug reports and pull requests are welcome on GitHub. See [CONTRIBUTING.md](CONTRIBUTING.md) for the
development workflow, and [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) for how we expect people to treat
each other in this project's spaces.

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for a history of releases.

## Licence

MIT. See [LICENSE.txt](LICENSE.txt). Copyright Sorare.
