# frozen_string_literal: true

module Administrate
  module MCP
    # Streamable HTTP endpoint for MCP JSON-RPC requests.
    # Handles POST (JSON-RPC), GET (SSE, rejected in stateless mode), and DELETE (session close).
    #
    # Authentication is bearer-token only. It inherits from ActionController::API so no session or
    # cookie ever reaches it: hosts share a session cookie across sibling subdomains, and a browser
    # that is signed into the admin UI must not thereby be able to drive the protocol endpoint.
    class JsonRpcController < ActionController::API
      AUTHORIZATION_ERROR_CODE = -32_003

      before_action :authenticate_admin!

      def handle
        server, server_context = setup_server
        status, headers, body = dispatch_request(server)

        if (authz_error = server_context[:authorization_errors].first)
          render_authorization_error(authz_error, extract_jsonrpc_id(body))
          return
        end

        self.status = status
        headers.each { |key, value| response.headers[key] = value }
        self.response_body = body
      end

      private

      def dispatch_request(server)
        rack_request = Rack::Request.new(request.env)
        server.transport.handle_request(rack_request)
      end

      def setup_server
        server_context = { admin: @identity.admin, scopes: @identity.scopes }
        [ServerBuilder.build(server_context:), server_context]
      end

      def authenticate_admin!
        @identity = Authentication.authenticate!(request)
      rescue Authentication::Error => e
        response.headers['X-Auth-Error'] = e.auth_error_type
        response.headers['WWW-Authenticate'] = www_authenticate_header
        render json: {
                 jsonrpc: '2.0',
                 error: {
                   code: e.jsonrpc_error_code,
                   message: e.message
                 },
                 id: nil
               },
               status: :unauthorized
      end

      def www_authenticate_header
        issuer = Administrate::MCP.config.issuer_for(request)
        "Bearer resource_metadata=\"#{issuer}/.well-known/oauth-protected-resource\""
      end

      def render_authorization_error(message, jsonrpc_id)
        response.headers['X-Auth-Error'] = 'forbidden'
        render json: {
                 jsonrpc: '2.0',
                 error: {
                   code: AUTHORIZATION_ERROR_CODE,
                   message:
                 },
                 id: jsonrpc_id
               },
               status: :forbidden
      end

      def extract_jsonrpc_id(body)
        JSON.parse(body.first)['id']
      rescue StandardError
        nil
      end
    end
  end
end
