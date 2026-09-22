# frozen_string_literal: true

module Administrate
  module MCP
    # Points an Administrate controller at a model and a dashboard the engine owns, rather than at
    # the pair Administrate would infer from the controller's own name.
    module ResourceController
      extend ActiveSupport::Concern

      included do
        class_attribute :mcp_resource_class, :mcp_dashboard_class
      end

      class_methods do
        def administrate_mcp_resource(resource_class, dashboard:)
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
