# frozen_string_literal: true

# Names Administrate::MCP::CloudflareAccess at initializer time, exactly as the README recipe tells a
# host to. Autoloading is not available this early, so the whole suite fails to boot if the class
# ever moves back under app/ — which is the only way this file earns its place.
Administrate::MCP.configure do |c|
  c.identity_fallback = Administrate::MCP::CloudflareAccess.new(
    team_domain: -> { ENV.fetch('CLOUDFLARE_ACCESS_TEAM_DOMAIN', nil) },
    audience: -> { ENV.fetch('CLOUDFLARE_ACCESS_MCP_AUD', nil) },
    find_admin: ->(email) { Admin.find_by(email:) }
  )
end
