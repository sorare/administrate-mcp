# frozen_string_literal: true

module Administrate
  module MCP
    # Maps resource names (e.g. "card", "card_factory/card_sample") to their dashboard and model
    # classes. Dashboards can declare MCP_DESCRIPTION to provide a human-readable description for
    # LLM tool discovery, MCP_BASE_SCOPE (a proc returning a relation) to override the model's
    # default scope, MCP_SKIPPED_ATTRIBUTES to keep attributes out of MCP reads, and
    # MCP_EXPOSED = false to leave the resource out of the registry altogether.
    # default scope for MCP reads — mirroring an admin controller's custom scoped_resource.
    class DashboardRegistry
      Entry =
        Struct.new(:dashboard_class, :model_class, :description, :base_scope, keyword_init: true) do
          def scope
            base_scope ? base_scope.call : model_class.all
          end
        end

      class << self
        def find(resource_name)
          key = resource_name.to_s.underscore.singularize
          registry[key]
        end

        def resource_names
          registry.keys.sort
        end

        def reset!
          @registry = nil
        end

        def registry
          @registry ||= build_registry
        end

        def build_registry
          dashboard_files.each_with_object({}) do |file, result|
            entry = build_entry(file)
            next unless entry

            result[entry.model_class.name.underscore] = entry
          rescue NameError
            next
          end
        end

        def build_entry(file)
          require_dependency file
          class_name = dashboard_class_name(file)
          dashboard_class = class_name.safe_constantize
          return unless dashboard_class
          return unless dashboard_class < Administrate::BaseDashboard
          return if dashboard_constant(dashboard_class, :MCP_EXPOSED) == false

          model_class = infer_model_class(dashboard_class, class_name)
          return unless model_class

          Entry.new(
            dashboard_class:,
            model_class:,
            description: dashboard_constant(dashboard_class, :MCP_DESCRIPTION),
            base_scope: dashboard_constant(dashboard_class, :MCP_BASE_SCOPE)
          )
        end

        def dashboard_files
          dashboard_roots.flat_map { |root| Dir[File.join(root, '**', '*_dashboard.rb')] }
        end

        def dashboard_class_name(file)
          root = dashboard_roots.find { |candidate| file.start_with?("#{candidate}/") }
          file.delete_prefix("#{root}/").delete_suffix('.rb').camelize
        end

        def infer_model_class(dashboard_class, class_name)
          dashboard_class.model
        rescue StandardError
          class_name.delete_suffix('Dashboard').safe_constantize
        end

        def skipped_attributes(dashboard)
          dashboard_class = dashboard.is_a?(Class) ? dashboard : dashboard.class
          Array(dashboard_constant(dashboard_class, :MCP_SKIPPED_ATTRIBUTES)).map(&:to_sym)
        end

        private

        def dashboard_roots
          Administrate::MCP.config.dashboard_directories
        end

        def dashboard_constant(dashboard_class, name)
          dashboard_class.const_defined?(name) ? dashboard_class.const_get(name) : nil
        end
      end
    end
  end
end
