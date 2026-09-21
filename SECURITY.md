# Security Policy

## Supported versions

The gem has not had a 1.0 release yet. Until it does, only the latest 0.x minor version is
supported with security fixes.

| Version          | Supported |
| ---------------- | --------- |
| Latest 0.x minor | Yes       |
| Older 0.x minors | No        |

## Reporting a vulnerability

Do not open a public issue for a security vulnerability.

Email security@sorare.com instead. Include:

- a description of the vulnerability and its impact
- the gem version, and the Rails and Administrate versions, if relevant
- steps to reproduce, or a minimal example
- any proof-of-concept code

We aim to give a first response within 5 business days. We practise coordinated disclosure:
give us a reasonable amount of time to investigate and release a fix before disclosing the issue
publicly, and we will credit you in the fix's changelog entry unless you prefer to stay anonymous.

## Scope

In scope: the engine's own code, including

- authentication (API keys, OAuth bearer tokens, the identity fallback mechanism)
- the OAuth 2.1 authorization server (client registration, the consent screen, PKCE, token
  issuance and revocation)
- the authorization adapters (`Authorization::Permissive`, `Authorization::Pundit`)
- field serialization, where a bug could leak an attribute a dashboard meant to hide
- the Cloudflare Access assertion verifier (`Administrate::MCP::CloudflareAccess`)

Out of scope: the host application's own dashboards, Pundit policies, and any configuration a host
supplies (for example, an `identity_fallback` or `authorization` object the host wrote itself). A
misconfigured host is a host-side issue, not a vulnerability in the engine.

## Security model in brief

- The JSON-RPC endpoint authenticates by bearer token only. It never reads the session cookie, so a
  browser signed into a host's admin UI cannot drive the protocol endpoint through that session.
- API keys are stored as a SHA-256 digest (`token_digest`) plus a stored prefix (`token_prefix`)
  that routes the token to the right check. The plaintext is never stored and is not recoverable.
- OAuth access and refresh tokens are stored in plaintext in
  `administrate_mcp_oauth_access_tokens`. This is a known limitation, not an oversight: anyone who
  can read that table can act as any admin who has authorized a client. Revoking a token (`revoke!`)
  is the remedy for a specific token; access tokens also expire after a week. The OAuth server can
  be turned off entirely with `config.oauth = false`, for hosts that run their own authorization
  flow in front of the application.
- `Administrate::MCP::CloudflareAccess` refuses every assertion when `team_domain` or `audience`
  resolves to blank. It does not fall through to accepting an unverified assertion and does not
  skip the audience check in that case; it returns no identity.
- `config.admin_active` lets a host revoke every credential an admin holds in one place: it is
  checked on every authenticated call, so deactivating an admin takes effect immediately even
  though the API keys and OAuth tokens they were issued are not themselves touched.
- A credential that is recognised but invalid, such as a revoked API key or an expired OAuth token,
  raises immediately and never falls through to `identity_fallback`. Only a bearer token the engine
  does not recognise at all reaches the fallback, so a revoked credential cannot be laundered into
  an externally-authenticated identity.
