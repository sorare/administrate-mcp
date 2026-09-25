# frozen_string_literal: true

require 'administrate/mcp/errors'

module Administrate
  module MCP
    module Authorization
      # Shared role gating. Roles are a host concept: an admin class that does not answer
      # `can_access?` cannot be gated on them, and saying so beats letting the call through.
      class Base
        # The message the built-in adapters raise. A caller that reformats a denial compares against
        # it to tell the generic message from one the host wrote.
        def self.denial_message(action, model_name)
          "Not authorized to #{action} #{model_name}"
        end

        def authorize!(admin, record_or_class, action)
          return if authorized?(admin, record_or_class, action)

          raise UnauthorizedError, Base.denial_message(action, model_name(record_or_class))
        end

        def authorized?(_admin, _record_or_class, _action)
          true
        end

        def authorize_roles!(admin, roles)
          return if roles.blank?

          unless admin.respond_to?(:can_access?)
            raise ConfigurationError,
                  "#{admin.class.name} does not respond to can_access?, so the required roles " \
                  "#{roles.join(', ')} cannot be checked. Give the admin class a can_access?(*roles) " \
                  'method, clear default_required_roles, or override authorize_roles! on the ' \
                  'authorization adapter.'
          end

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
