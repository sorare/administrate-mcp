# frozen_string_literal: true

require 'administrate/mcp/authorization/base'

module Administrate
  module MCP
    module Authorization
      # Runs the host's Pundit policy for the resource, exactly as the Administrate UI does.
      class Pundit < Base
        def authorize!(admin, record_or_class, action)
          policy = policy_for(admin, record_or_class)
          return if policy.public_send(action)

          raise UnauthorizedError, Base.denial_message(action, model_name(record_or_class))
        end

        def authorized?(admin, record_or_class, action)
          authorize!(admin, record_or_class, action)
          true
        rescue UnauthorizedError, ::Pundit::NotDefinedError
          false
        end

        private

        def policy_for(admin, record_or_class)
          ::Pundit::PolicyFinder.new(record_or_class).policy!.new(admin, record_or_class)
        end
      end
    end
  end
end
