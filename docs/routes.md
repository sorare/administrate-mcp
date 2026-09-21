# Routes

[Back to README](../README.md)

The consent screen must be served on the admin origin, where the admin's session lives, while the
JSON-RPC and metadata endpoints live on a dedicated MCP origin. Draw each set inside your own
constraints:

```ruby
Rails.application.routes.draw do
  constraints ->(request) { request.subdomain == 'admin-mcp' } do
    Administrate::MCP::Routes.draw_mcp_origin(self)
  end

  constraints subdomain: 'admin' do
    Administrate::MCP::Routes.draw_admin_origin(self)
  end
end
```

`draw_mcp_origin` adds `/.well-known/oauth-protected-resource`,
`/.well-known/oauth-authorization-server`, `POST /oauth/register`, `POST /oauth/token` and the
JSON-RPC endpoint at `/`. `draw_admin_origin` adds `GET` and `POST /mcp/oauth/authorize`; pass
`path:` to move it. With `config.oauth` false the OAuth routes are left out of both. See
[OAuth](oauth.md) for what that means.

Both sets have to sit at the root of their origin. The metadata documents the engine publishes name
the token, registration and JSON-RPC endpoints as absolute paths, `/oauth/token`, `/oauth/register`,
`/`, so mounting the engine under a prefix would advertise paths that do not answer. If you serve
everything on a single origin, call both helpers on that origin rather than mounting the engine.
