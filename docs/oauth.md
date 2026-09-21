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

A verifier for Cloudflare Access managed OAuth ships with the gem, for hosts that run authentication
at the edge instead of through this server: see
[Identity fallback](authentication.md#identity-fallback) in the authentication guide.

## Dynamic Client Registration

Registration accepts `localhost`, `127.0.0.1`, `::1` and any `*.localhost` subdomain as loopback
hosts, and issues authorization codes to them over plain http rather than requiring https.
`*.localhost` covers parallel development checkouts running on different subdomains. The match is
made on the parsed hostname, so a redirect URI on a host such as `localhost.attacker.com` is
rejected. Set `allow_localhost_redirects = false` to require https for every redirect URI, including
loopback ones.

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
