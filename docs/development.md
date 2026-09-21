# Development

[Back to README](../README.md)

```sh
bundle install
bundle exec rspec
bundle exec rubocop
```

You need a reachable PostgreSQL server; the test suite creates its own database on first run (the
spec helper catches `ActiveRecord::NoDatabaseError` and calls `ActiveRecord::Tasks::DatabaseTasks.create`),
so no separate `createdb` step is needed. Point the specs at another Postgres with
`ADMINISTRATE_MCP_DB_HOST`, `_PORT`, `_USER`, `_PASSWORD` and `_NAME`.

The dummy application under `spec/dummy` has an `Admin`, a `Widget` (with `MCP_BASE_SCOPE` and
collection filters) and a `Gadget` (with a `belongs_to` and an `mcp_action`).

See [CONTRIBUTING.md](../CONTRIBUTING.md) for how to propose a change.
