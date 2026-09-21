# OAuth

[Back to README](../README.md)

The engine ships a complete OAuth 2.1 authorization server: Dynamic Client Registration, a consent
screen, PKCE, refresh tokens, and the two discovery documents clients read to find all of it. That is
the default, and for most hosts it is the whole story.

It does not fit a deployment where something in front of the application already does this. Cloudflare
Access managed OAuth, for instance, serves both discovery documents at its own edge and points
clients at `<team>.cloudflareaccess.com` for authorization, token, registration and revocation. The
engine's endpoints are then unreachable, and advertising them only gives clients a second, broken
answer. Turn the server off:

```ruby
Administrate::MCP.configure do |c|
  c.oauth = false
end
```

`Routes.draw_mcp_origin` then draws the JSON-RPC endpoint and nothing else: no `/.well-known/*`, no
`/oauth/register`, no `/oauth/token`, and `Routes.draw_admin_origin` becomes a no-op, so you can
leave both calls where they are. API keys keep working. An OAuth token presented while the server is
off is a bearer token the engine does not recognise, and goes to `identity_fallback` like any other.

The models and migrations still ship, and the tables are never queried while `oauth` is false, so a
host that never ran that migration boots and serves normally. `default_client_name` and
`allow_localhost_redirects` have nothing to act on and are inert.

## Cloudflare Access

`Administrate::MCP::CloudflareAccess` verifies the assertion Access attaches to every request it lets
through. It answers `call(request)`, so it can be assigned to `identity_fallback` directly, in the
same `config/initializers/administrate_mcp.rb` as the rest of your configuration: no `to_prepare`
wrapper and no deferred reference, the class is requirable the moment the gem is:

```ruby
Administrate::MCP.configure do |c|
  c.oauth = false
  c.identity_fallback = Administrate::MCP::CloudflareAccess.new(
    team_domain: -> { ENV.fetch('CLOUDFLARE_ACCESS_TEAM_DOMAIN', nil) },
    audience: -> { ENV.fetch('CLOUDFLARE_ACCESS_MCP_AUD', nil) },
    find_admin: ->(email) { Administrator.find_by(email:) },
    scopes_for: ->(admin) { admin.mcp_write_access? ? ['write'] : [] }
  )
end
```

It reads the `Cf-Access-Jwt-Assertion` header, verifies the RS256 signature against the JWKS at
`<team_domain>/cdn-cgi/access/certs` (cached an hour, refetched once when a key id is unknown, which
is what a key rotation looks like), and checks the issuer and audience. `find_admin` receives the
lowercased email and `scopes_for` the admin it returned; returning no admin raises
`ExternalIdentityError` with `X-Auth-Error: cloudflare_access`.

`team_domain` and `audience` each take a value or a callable. Pass lambdas, as above. You build this
object in an initializer, and a plain `ENV.fetch` there is read once at boot: in an environment where
those variables are set later, or not set at all, the object would be permanently unconfigured and
would quietly refuse every request. A lambda is re-read on each call, so the settings can arrive
after boot and a spec can change them.

A blank `team_domain` or `audience` means the verifier accepts **nothing**. It returns nil for every
assertion without calling Cloudflare; it does not fall through to an unverified one, and it does not
skip the audience check. Configuring it everywhere and enabling it per environment is therefore safe,
but so is getting it wrong: a typo in the audience variable refuses all callers rather than admitting
assertions minted for some other Access application.

Access must be in front of the JSON-RPC origin for this to mean anything: the assertion is only
trustworthy because nothing can reach the application without passing through Access.

## Rate limiting

The gem does not depend on rack-attack. If you use it, these are the throttles to add, or call
`Administrate::MCP::RackAttack.throttles(host: 'admin-mcp')` from your own initializer, which
registers exactly these:

| Name                        | Request                                | Limit                |
| --------------------------- | -------------------------------------- | -------------------- |
| `mcp_oauth/register/ip`     | `POST /oauth/register` on the MCP host | 5 per minute per IP  |
| `mcp_oauth/register/ip-day` | `POST /oauth/register` on the MCP host | 50 per day per IP    |
| `mcp_oauth/token/ip`        | `POST /oauth/token` on the MCP host    | 10 per minute per IP |
| `mcp_oauth/authorize/ip`    | `GET /mcp/oauth/authorize`             | 20 per minute per IP |
