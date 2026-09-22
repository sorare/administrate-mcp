# frozen_string_literal: true

module Administrate
  module MCP
    # Points an Administrate controller at a model the engine owns, rather than at the one
    # Administrate would infer from the controller's own name.
    #
    # The dashboard is left alone on purpose. Administrate finds it by camelizing the controller's
    # name, and a host that registers MCP as an inflection acronym spells that constant differently
    # from one that does not. Naming it here would be right in one host and an autoloading error in
    # the other, so each host declares its own dashboard, usually a subclass of the engine's.
    module ResourceController
      extend ActiveSupport::Concern

      included do
        class_attribute :mcp_resource_class, :mcp_dashboard_class
      end

      class_methods do
        # `dashboard` is only needed for a dashboard Administrate cannot find from the controller's
        # own name.
        def administrate_mcp_resource(resource_class, dashboard: nil)
          self.mcp_resource_class = resource_class
          self.mcp_dashboard_class = dashboard
        end
      end

      def resource_class
        mcp_resource_class
      end

      private

      def resource_resolver
        @resource_resolver ||=
          Administrate::MCP::ResourceResolver.new(
            controller_path,
            resource_class: mcp_resource_class,
            dashboard_class: mcp_dashboard_class
          )
      end
    end
  end
end
