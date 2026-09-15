# frozen_string_literal: true

module Administrate
  module MCP
    # Route helpers for hosts that serve the protocol endpoints and the consent screen on different
    # origins. Call them from inside the host's own `constraints` blocks.
    module Routes
      AUTHORIZE_PATH = '/mcp/oauth/authorize'

      class << self
        def draw_mcp_origin(mapper)
          mapper.get '/.well-known/oauth-protected-resource', to: 'administrate/mcp/oauth#resource_metadata'
          mapper.get '/.well-known/oauth-authorization-server', to: 'administrate/mcp/oauth#server_metadata'
          mapper.post '/oauth/register', to: 'administrate/mcp/oauth#register'
          mapper.post '/oauth/token', to: 'administrate/mcp/oauth#token'
          mapper.match '/', to: 'administrate/mcp/json_rpc#handle', via: %i[get post delete]
        end

        def draw_admin_origin(mapper, path: AUTHORIZE_PATH)
          mapper.get path, to: 'administrate/mcp/oauth#authorize'
          mapper.post path, to: 'administrate/mcp/oauth#approve'
        end
      end
    end
  end
end
