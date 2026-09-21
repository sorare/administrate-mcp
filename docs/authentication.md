# Authentication

[Back to README](../README.md)

A request is authenticated in this order: an API key, then, if `oauth` is enabled, the engine's own
OAuth access token, then `identity_fallback`. The first credential the request presents that the
engine recognises settles the call; `identity_fallback` is only consulted when nothing the engine
issued matched.

**API keys.** Create one yourself and hand the plaintext to the user once:

```ruby
token = Administrate::MCP::ApiKey.generate_token
Administrate::MCP::ApiKey.create!(admin:, name: 'Laptop', token_digest: Administrate::MCP::ApiKey.digest_token(token),
                                  token_prefix: token[0, 13])
```

Only the digest is stored. Keys are read-only unless `write_access` is set.

If you are migrating keys that were issued before you adopted this gem, set `api_key_token_prefix`
to the prefix those keys already carry. The plaintext is not recoverable, only its digest and the
first 13 characters are stored in `token_prefix`, so a changed prefix makes every existing key stop
matching, and the holders have to be issued new ones.

**OAuth 2.1.** Clients register themselves, send the user to the consent screen on the admin origin,
and exchange the code with PKCE. Access tokens last a week, authorization codes ten minutes, and
refreshing revokes the old token. See [OAuth](oauth.md) for turning it off.

## Identity fallback

Some deployments authenticate the caller before the request reaches Rails. Cloudflare Access managed
OAuth is the common case: Access resolves the client's bearer token at its own edge and forwards an
assertion, so the application only ever sees a token no row of ours matches. `identity_fallback` is
where you turn that assertion into an admin:

```ruby
c.identity_fallback = lambda do |request|
  email = CloudflareAccess.email(request) # your own verification of the Access JWT
  next nil unless email

  admin = Administrator.find_by(email:)
  unless admin
    raise Administrate::MCP::Authentication::ExternalIdentityError.new(
      "No admin account for #{email}",
      auth_error_type: 'cloudflare_access'
    )
  end

  Administrate::MCP::Authentication::Identity.new(admin:, scopes: ['write'])
end
```

It is consulted only when nothing the engine issued matched: an absent `Authorization` header, or a
bearer token that is neither an API key by prefix nor a row in the OAuth tokens table. A key or token
that _is_ recognised and then fails, revoked, expired, unknown digest, raises as before and never
reaches the fallback, so a revoked credential cannot be laundered into an Access identity. Returning
nil leaves that refusal in place. Raising `ExternalIdentityError` is how you say "I know who
this is and they have no account": it answers 401 with the `auth_error_type` you pass as
`X-Auth-Error` and JSON-RPC code `-32001`. `admin_active` applies to fallback identities too.

A credential outlives the admin who holds it: revoking someone's admin role, deactivating or
anonymizing their account does nothing to a key or token they were already issued, and a tool such as
`sidekiq_retries` never consults the authorization adapter. Set `admin_active` so every call
re-checks the person, not only the credential.

The JSON-RPC endpoint authenticates by bearer token only and never reads the session cookie: hosts
routinely share a session across sibling subdomains, and a browser signed into the admin UI must not
thereby be able to drive the protocol endpoint.

### Cloudflare Access

Edge-managed OAuth in front of an MCP server is a common deployment, so one verifier for it ships
with the gem. `Administrate::MCP::CloudflareAccess` implements the `identity_fallback` contract shown
above: a callable taking the request, returning an `Authentication::Identity` or nil, and raising
`ExternalIdentityError` to signal an identity Access has asserted but that has no admin account. Use
it as a template for any other provider.

It answers `call(request)`, so it can be assigned to `identity_fallback` directly, in the same
`config/initializers/administrate_mcp.rb` as the rest of your configuration: no `to_prepare` wrapper
and no deferred reference, the class is requirable the moment the gem is. It lives in `lib/`, not
`app/`, alongside `Routes` and `RackAttack`, so an initializer can name it before autoloading is
available.

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

`team_domain` and `audience` each take a value or a callable. Pass lambdas, as above. The object is
built once, in an initializer, and reads these two settings again on every call rather than at
construction: a plain `ENV.fetch` at construction time would be read once at boot, and in an
environment where those variables are set later, or not set at all, the object would be permanently
unconfigured and would quietly refuse every request. A lambda re-read on each call lets the settings
arrive after boot, and lets a spec change them.

A blank `team_domain` or `audience` means the verifier accepts **nothing**. It returns nil for every
assertion without calling Cloudflare; it does not fall through to an unverified one, and it does not
skip the audience check. Configuring it everywhere and enabling it per environment is therefore safe,
but so is getting it wrong: a typo in the audience variable refuses all callers rather than admitting
assertions minted for some other Access application.

Access must be in front of the JSON-RPC origin for this to mean anything: the assertion is only
trustworthy because nothing can reach the application without passing through Access.
