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
refreshing revokes the old token. See [OAuth](oauth.md) for turning it off and for the Cloudflare
Access verifier that ships with the gem.

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
nil leaves the original refusal in place. Raising `ExternalIdentityError` is how you say "I know who
this is and they have no account": it answers 401 with the `auth_error_type` you pass as
`X-Auth-Error` and JSON-RPC code `-32001`. `admin_active` applies to fallback identities too.

A credential outlives the admin who holds it: revoking someone's admin role, deactivating or
anonymizing their account does nothing to a key or token they were already issued, and a tool such as
`sidekiq_retries` never consults the authorization adapter. Set `admin_active` so every call
re-checks the person, not only the credential.

The JSON-RPC endpoint authenticates by bearer token only and never reads the session cookie: hosts
routinely share a session across sibling subdomains, and a browser signed into the admin UI must not
thereby be able to drive the protocol endpoint.
