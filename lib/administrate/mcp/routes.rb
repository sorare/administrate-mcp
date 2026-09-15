# frozen_string_literal: true

module Administrate
  module MCP
    # Route helpers for hosts that serve the protocol endpoints and the consent screen on different
    # origins. Call them from inside the host's own `constraints` blocks.
    #
    # Endpoints are Rack lambdas rather than "controller#action" strings so that resolving them
    # never depends on an `MCP` acronym being registered in the host's global inflections.
    module Routes
      AUTHORIZE_PATH = '/mcp/oauth/authorize'

      class << self
        def draw_mcp_origin(mapper)
          mapper.get '/.well-known/oauth-protected-resource', to: o_auth(:resource_metadata)
          mapper.get '/.well-known/oauth-authorization-server', to: o_auth(:server_metadata)
          mapper.post '/oauth/register', to: o_auth(:register)
          mapper.post '/oauth/token', to: o_auth(:token)
          mapper.match '/', to: json_rpc, via: %i[get post delete]
        end

        def draw_admin_origin(mapper, path: AUTHORIZE_PATH)
          mapper.get path, to: o_auth(:authorize)
          mapper.post path, to: o_auth(:approve)
        end

        def json_rpc
          ->(env) { Administrate::MCP::JsonRpcController.action(:handle).call(env) }
        end

        def o_auth(action)
          ->(env) { Administrate::MCP::OAuthController.action(action).call(env) }
        end
      end
    end
  end
end
