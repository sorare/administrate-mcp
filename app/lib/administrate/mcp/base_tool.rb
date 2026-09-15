# frozen_string_literal: true

module Administrate
  module MCP
    # Base class for all MCP tools — provides role gating, auditing, and response helpers.
    class BaseTool < ::MCP::Tool
      UnauthorizedError = Administrate::MCP::UnauthorizedError
      InvalidArgumentError = Administrate::MCP::InvalidArgumentError

      class << self
        def requires_roles(*roles)
          @required_roles = roles.flatten
        end

        def required_roles
          @required_roles || Administrate::MCP.config.default_required_roles
        end

        def requires_scope(*scopes)
          @required_scopes = scopes.map(&:to_sym)
        end

        def required_scopes
          @required_scopes || []
        end

        def call(server_context:, **args)
          instrument(server_context) { call_with_context(server_context, **args) }
        rescue UnauthorizedError => e
          (server_context[:authorization_errors] ||= []).push(e.message)
          error_response(e.message)
        rescue InvalidArgumentError => e
          error_response(e.message)
        rescue StandardError => e
          error_response("Internal error: #{e.message}")
        end

        private

        def instrument(server_context, &)
          Administrate::MCP.config.instrument.call(tool_name: name_value, admin: server_context[:admin], &)
        end

        def call_with_context(server_context, **args)
          admin = server_context[:admin]
          check_scopes!(server_context)
          check_roles!(admin, **args)
          audit!(admin, args, server_context)
          execute(admin:, **args)
        end

        def check_scopes!(server_context)
          return if required_scopes.empty?

          granted = (server_context[:scopes] || []).map(&:to_sym)
          missing = required_scopes - granted
          return if missing.empty?

          raise UnauthorizedError, "Missing required scope(s): #{missing.join(', ')}"
        end

        def check_roles!(admin, **)
          Administrate::MCP.config.authorization.authorize_roles!(admin, required_roles)
        end

        def audit!(admin, args, server_context)
          Administrate::MCP.config.on_tool_call.call(
            tool_name: name_value,
            admin:,
            arguments: args,
            scopes: server_context[:scopes] || []
          )
        end

        def execute(admin:, **args)
          raise NotImplementedError, "#{name} must implement .execute"
        end

        def text_response(text)
          ::MCP::Tool::Response.new([{ type: 'text', text: }])
        end

        def json_response(data)
          ::MCP::Tool::Response.new([{ type: 'text', text: data.to_json }])
        end

        def error_response(message)
          ::MCP::Tool::Response.new([{ type: 'text', text: message }], error: true)
        end
      end
    end
  end
end
