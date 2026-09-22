# frozen_string_literal: true

module Administrate
  module MCP
    # Administrate derives the model and the dashboard from the controller path, which cannot name a
    # class living inside the engine's namespace. This resolver takes both from the controller.
    class ResourceResolver < Administrate::ResourceResolver
      attr_reader :resource_class, :dashboard_class

      def initialize(controller_path, resource_class:, dashboard_class:)
        super(controller_path)
        @resource_class = resource_class
        @dashboard_class = dashboard_class
      end

      # The form builder names its parameters after the record, so the controller has to read them
      # under the same key whatever path the host mounted it at.
      def resource_name
        resource_class.model_name.param_key.to_sym
      end
    end
  end
end
