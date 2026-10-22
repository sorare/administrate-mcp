# frozen_string_literal: true

module Administrate
  module MCP
    # Base class for all MCP tools — provides role gating, auditing, and response helpers.
    class BaseTool < ::MCP::Tool
      UnauthorizedError = Administrate::MCP::UnauthorizedError
      ResourceForbiddenError = Administrate::MCP::ResourceForbiddenError
      InvalidArgumentError = Administrate::MCP::InvalidArgumentError

      RESERVED_ARGUMENTS = %i[admin].freeze

      class << self
        def input_schema(value = NOT_SET)
          reject_reserved_properties!(value) if value.is_a?(Hash)
          super
        end

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
        rescue ResourceForbiddenError, InvalidArgumentError => e
          error_response(e.message)
        rescue UnauthorizedError => e
          (server_context[:authorization_errors] ||= []).push(e.message)
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
          reject_reserved_arguments!(args)
          execute(**args, admin:, **execute_context(server_context))
        end

        def execute_context(_server_context)
          {}
        end

        def reject_reserved_arguments!(args)
          reserved = args.keys & RESERVED_ARGUMENTS
          return if reserved.empty?

          raise InvalidArgumentError, "Reserved argument(s) cannot be passed: #{reserved.join(', ')}"
        end

        def reject_reserved_properties!(schema)
          properties = (schema[:properties] || schema['properties'] || {}).keys.map(&:to_sym)
          reserved = properties & RESERVED_ARGUMENTS
          raise ArgumentError, "#{name}: reserved input property name(s): #{reserved.join(', ')}" if reserved.any?
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

        def json_response(data, structured: false)
          ::MCP::Tool::Response.new([{ type: 'text', text: data.to_json }], structured_content: (data if structured))
        end

        def error_response(message, data: nil)
          structured_content = { error: message, data: } unless data.nil?
          ::MCP::Tool::Response.new([{ type: 'text', text: message }], error: true, structured_content:)
        end
      end
    end
  end
end
