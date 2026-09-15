# frozen_string_literal: true

require 'administrate/base_dashboard'

module Administrate
  module MCP
    # Adds the MCP declarations to every Administrate dashboard: the `mcp_action` macro and the
    # `mcp_action_specs` store it writes to. `MCP_DESCRIPTION` and `MCP_BASE_SCOPE` stay plain
    # constants, read by the registry.
    module DashboardExtension
      module ClassMethods
        def mcp_action(name, **, &)
          self.mcp_action_specs = [*mcp_action_specs, Administrate::MCP::Actions.build_spec(name, **, &)]
        end
      end

      def self.install!
        return if Administrate::BaseDashboard.respond_to?(:mcp_action_specs)

        Administrate::BaseDashboard.class_attribute :mcp_action_specs, default: []
        Administrate::BaseDashboard.singleton_class.prepend(ClassMethods)
      end
    end
  end
end
