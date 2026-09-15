# frozen_string_literal: true

require 'administrate/mcp/errors'

module Administrate
  module MCP
    module Authorization
      # Shared role gating. Roles are a host concept: an admin that does not answer `can_access?`
      # is never refused on role grounds.
      class Base
        def authorize!(admin, record_or_class, action)
          return if authorized?(admin, record_or_class, action)

          raise UnauthorizedError, "Not authorized to #{action} #{model_name(record_or_class)}"
        end

        def authorized?(_admin, _record_or_class, _action)
          true
        end

        def authorize_roles!(admin, roles)
          return if roles.blank?
          return unless admin.respond_to?(:can_access?)
          return if admin.can_access?(*roles)

          raise UnauthorizedError, "Insufficient permissions. Required roles: #{roles.join(', ')}"
        end

        private

        def model_name(record_or_class)
          record_or_class.is_a?(Class) ? record_or_class.name : record_or_class.class.name
        end
      end
    end
  end
end
