# frozen_string_literal: true

module Administrate
  module MCP
    module Tools
      # Lists available admin resources. Without a resource param, returns a lightweight catalog
      # (name + description). With a resource param, returns full detail (fields + filters).
      class AdminResourceListResources < AdminDashboardTool
        tool_name 'admin_resource_list_resources'
        description 'Discover available admin resources. ' \
                    'Without a resource param: returns the resource names you can read (lightweight catalog). ' \
                    'With a resource param: returns fields and filters for that resource.'
        annotations read_only_hint: true, destructive_hint: false, open_world_hint: true

        input_schema(
          properties: {
            resource: {
              type: 'string',
              description:
                'Resource name to inspect (optional). When provided, returns fields and filters for that ' \
                'resource. Must be an exact name from the no-argument catalog — many resources are ' \
                'namespaced (e.g. "shop/order") and bare names are not aliased.'
            }
          }
        )

        def self.execute(admin:, resource: nil)
          return detail_response(admin, resource) if resource.present?

          catalog_response(admin)
        end

        def self.catalog_response(admin)
          resources =
            DashboardRegistry.resource_names.filter_map do |name|
              entry = DashboardRegistry.find(name)
              next unless entry
              next unless authorized?(admin, entry.model_class, :index?)

              result = { name: }
              result[:description] = entry.description if entry.description.present?
              result
            end

          json_response(resources)
        end

        def self.detail_response(admin, resource_name)
          entry = find_dashboard_entry!(admin, resource_name)
          authorize_resource!(admin, entry.model_class, :index?)

          json_response(build_detail(resource_name, entry))
        end

        def self.build_detail(name, entry)
          dashboard = entry.dashboard_class.new
          result = { name:, fields: FieldSerializer.exposed_attributes(dashboard).map(&:to_s) }
          result[:description] = entry.description if entry.description.present?
          enrich_detail!(result, entry, dashboard)
          result
        end

        def self.enrich_detail!(result, entry, dashboard)
          filters = collection_filters(entry.dashboard_class, entry.model_class)
          result[:filters] = filters if filters.present?
          expandable = expandable_associations(dashboard)
          result[:expandable] = expandable if expandable.present?
        end

        def self.expandable_associations(dashboard)
          dashboard.attribute_types.filter_map do |attr_name, spec|
            next unless FieldSerializer.expandable_field?(FieldSerializer.resolve_field_class(spec))

            attr_name.to_s
          end
        end

        def self.collection_filters(dashboard_class, model_class)
          dashboard_filters = dashboard_defined_filters(dashboard_class)
          dashboard_filter_names = dashboard_filters.to_set { |f| f[:name] }

          assoc_filters =
            association_columns(model_class)
            .reject { |col| dashboard_filter_names.include?(col) }
            .sort
            .map { |col| { name: col, type: 'value' } }

          dashboard_filters + assoc_filters
        end

        def self.dashboard_defined_filters(dashboard_class)
          return [] unless dashboard_class.const_defined?(:COLLECTION_FILTERS, false)

          dashboard_class
            .const_get(:COLLECTION_FILTERS, false)
            .map do |name, filter|
              type = filter.arity == 1 ? 'boolean' : 'value'
              { name: name.to_s, type: }
            end
        end
      end
    end
  end
end
