# Design decisions

[Back to README](../README.md)

- **Everything host-specific is configuration, not a subclass.** The engine references no constant
  it does not own, at load time or at run time. That is why field serializers are keyed on class
  _names_, why the Sidekiq stats tool needs a provider object, and why auditing and instrumentation
  are procs.
- **`admin`, not `administrator`.** The owner association, the `server_context` key and the
  `execute(admin:)` keyword all use `admin`. Applications that called the Sorare originals with
  `administrator:` need to rename that one keyword in their own tools and `mcp_action` blocks.
- **No foreign key on `admin_id`.** Hosts disagree about which table admins live in, and some forbid
  cross-table constraints. The column is indexed; referential integrity is the host's call.
- **Roles live on the authorization adapter.** Roles are an authorization concern, and hosts that
  have none get the behaviour for free: an admin that does not answer `can_access?` is never refused
  on role grounds. `default_required_roles` supplies the gate for tools that declare none;
  `report_mcp_improvement` opts out, because reporting a bad description is not privileged.
- **Files named `o_auth_*.rb`, classes named `OAuth*`.** Zeitwerk derives the constant from the file
  name, and `oauth_access_token.rb` would produce `OauthAccessToken` unless the host registered an
  `OAuth` acronym globally. Naming the file `o_auth_access_token.rb` gets the right constant with no
  inflection at all. The only inflection the engine registers is `mcp` to `MCP`, and it registers it
  on the autoloader rather than in `ActiveSupport::Inflector`, so your application's `camelize` is
  untouched.
- **Routes are Rack lambdas, not `"controller#action"` strings.** Rails resolves those strings
  through the global inflections, which would have reintroduced the acronym requirement.
- **Tool names are unchanged:** `admin_resource_list`, `admin_resource_show`,
  `admin_resource_list_resources`, `report_mcp_improvement`, `sidekiq_stats`, `sidekiq_retries`, so
  existing clients keep working.
- **`FastSearch` ships with the engine.** The list tool searches exactly by default, with `*` as the
  only wildcard, so searching an id or a slug does not match every row that contains it. It is a
  subclass of `Administrate::Search` and calls methods that class treats as internal
  (`search_attributes`, `searchable_fields`, `query_table_name`, `column_to_query`), which is why the
  gemspec pins administrate below 2. It differs from `Administrate::Search` in one deliberate way:
  every comparison casts the column to text, so a plain word searched against a uuid `id` column
  returns no rows instead of raising `PG::InvalidTextRepresentation` and aborting the transaction.
- **Registration accepts more loopback hosts than the original.** `localhost`, `127.0.0.1`, `::1` and
  any `*.localhost` subdomain register and receive codes over plain http; the Sorare original allowed
  only `localhost` and `127.0.0.1`. `*.localhost` is what parallel development checkouts use, and the
  match is on the parsed hostname, so `localhost.attacker.com` is still rejected. Set
  `allow_localhost_redirects = false` to require https everywhere.
- **`Field::Text` and `Field::Url` serialize a nil as `null`.** They are registered as scalars, so an
  empty value comes back as `null` rather than the `""` the original's `to_s` fallback produced.
- **`report_mcp_improvement` requires no role.** The original listed every role the host had, which
  in practice admitted everyone except an admin with no roles at all; it is now open to any
  authenticated admin.
- **Authentication is extensible, not replaceable.** `identity_fallback` runs only after the
  engine's own credentials have had their turn and only when none of them matched, so a host can add
  an external identity source, an edge proxy, an SSO assertion, without weakening the tokens the
  engine issues.
- **The OAuth server is optional, not removable.** A host behind an edge proxy that runs its own
  authorization flow sets `oauth = false` and the engine stops advertising and serving endpoints that
  cannot work there. Everyone else gets a full OAuth 2.1 server with no setup, which is what makes
  the gem usable on its own.
- **`CloudflareAccess` takes its collaborators in its constructor.** The team domain, audience, admin
  lookup and scope decision are all arguments rather than environment variables or model calls, so
  the class knows nothing about any particular application and can be built twice with different
  audiences in the same process. The two settings resolve on every call rather than at construction,
  because the object is built in an initializer and the environment it reads is not always readable
  there. The class itself ships in `lib` rather than `app`, alongside `Routes` and `RackAttack`, for
  the same reason: an initializer has to be able to name it, and autoloading is not available that
  early.
- **Feedback services are plain objects.** `ReportImprovement` and `CleanOldFeedbacks` return a
  result struct and do no scheduling; the host decides how and when to run them.
