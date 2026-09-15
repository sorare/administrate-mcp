# frozen_string_literal: true

module Administrate
  module MCP
    module Tools
      # Lists/searches admin resources using Administrate dashboard definitions and search.
      class AdminResourceList < AdminDashboardTool
        MAX_PER_PAGE = 25
        MAX_EXPAND = 2

        def self.policy_action
          :index?
        end

        tool_name 'admin_resource_list'
        description 'Search and list admin resources. ' \
                      'Supports text search, filters, sorting, field selection, and HasMany expansion.'
        annotations read_only_hint: true, destructive_hint: false, open_world_hint: true

        input_schema(
          properties: {
            resource: {
              type: 'string',
              description:
                'Resource type name (e.g., "card", "user", "player"). ' \
                  'Use admin_resource_list_resources with no arguments to see available ones. ' \
                  'Many resources are namespaced (e.g. "shop/order") and bare names are not aliased. ' \
                  'An unrecognised name currently surfaces as an authorization error, not a "not found" ' \
                  'error, so treat an auth failure here as a likely wrong resource name and re-check the ' \
                  'catalog rather than assuming the server is unavailable.'
            },
            query: {
              type: 'string',
              description:
                'Search query (optional). Searches across searchable string fields ' \
                  '(e.g., slug, display_name). Uses exact matching by default — ' \
                  'use * as wildcard for partial matches (e.g., "*stellar*ligue*").'
            },
            filters: {
              type: 'object',
              description:
                'Filters to apply (optional). Keys are filter names, values are filter arguments. ' \
                  'Use admin_resource_list_resources to discover available filters per resource.'
            },
            sort: {
              type: 'string',
              description: 'Field to sort by (e.g., "created_at", "ranking"). Must be a valid dashboard attribute.'
            },
            sort_direction: {
              type: 'string',
              enum: %w[asc desc],
              description: 'Sort direction (default: desc)'
            },
            fields: {
              type: 'array',
              items: {
                type: 'string'
              },
              description: 'Specific fields to return (optional). Returns all collection fields if omitted.'
            },
            expand: {
              type: 'array',
              items: {
                type: 'string'
              },
              description:
                'HasMany associations to expand inline instead of counts. Max 2 associations. An expanded ' \
                  'association returns {count, items}: count is the association total, and items is capped at ' \
                  '25 rows. Both ship in the same response, so always compare them — count > items.length ' \
                  'means the list is clipped and items is NOT the full set. items also come back in no ' \
                  'guaranteed order: the sort_by / direction declared on the dashboard attribute is not ' \
                  'applied on this path, so a clipped expand is an arbitrary slice and not the newest rows — ' \
                  'reading recency off it can report a year-old row as the latest one. There is no way to page ' \
                  'past the cap or to sort here: when you need the remaining rows, or the most recent ones, ' \
                  'list the related resource directly with a filter on this record and an explicit sort.'
            },
            page: {
              type: 'number',
              description: 'Page number (default: 1)'
            },
            per_page: {
              type: 'number',
              description: "Results per page (default: 10, max: #{MAX_PER_PAGE})"
            }
          },
          required: %w[resource]
        )

        # rubocop:disable-next Metrics/ParameterLists, Lint/UnusedMethodArgument
        def self.execute(
          admin:,
          resource:,
          query: nil,
          filters: nil,
          sort: nil,
          sort_direction: 'desc',
          fields: nil,
          expand: nil,
          page: 1,
          per_page: 10
        )
          entry = find_dashboard_entry!(resource)
          dashboard = entry.dashboard_class.new
          per_page = per_page.to_i.clamp(1, MAX_PER_PAGE)
          page = [page.to_i, 1].max
          scope = build_scope(entry, dashboard, query, filters)
          scope = apply_sort(scope, dashboard, sort, sort_direction)
          records = scope.page(page).per(per_page)

          json_response(build_response(records, dashboard, page, per_page, fields:, expand:))
        end

        def self.build_response(records, dashboard, page, per_page, fields: nil, expand: nil)
          attrs, expand_set =
            resolve_attributes_and_expansions(dashboard, fields, expand, :collection_attributes, MAX_EXPAND)
          columns = FieldSerializer.resolve_columns(dashboard, attrs)

          {
            columns: %w[url] + columns.map(&:to_s),
            rows:
              records.map do |r|
                [FieldSerializer.admin_url_for(r)] +
                  FieldSerializer.serialize_row(r, dashboard, columns:, expand: expand_set)
              end,
            meta: {
              page:,
              per_page:,
              total_count: records.total_count,
              total_pages: records.total_pages
            }
          }
        end

        def self.build_scope(entry, dashboard, query, filters)
          scope = entry.scope
          scope = apply_includes(scope, dashboard)
          scope = apply_search(scope, dashboard, query) if query.present?
          scope = apply_filters(scope, entry, filters) if filters.present?
          scope
        end

        def self.apply_includes(scope, dashboard)
          includes = dashboard.collection_includes
          includes.any? ? scope.preload(*includes) : scope
        end

        def self.apply_filters(scope, entry, filters)
          dashboard_filters = dashboard_collection_filters(entry.dashboard_class)
          valid_columns = association_columns(entry.model_class)

          reject_unknown!('filters', filters.keys, dashboard_filters.keys.map(&:to_s) + valid_columns.to_a)

          filters.each { |name, value| scope = apply_single_filter(scope, name, value, dashboard_filters, valid_columns) }
          scope
        end

        def self.apply_single_filter(scope, name, value, dashboard_filters, valid_columns)
          dashboard_filter = dashboard_filters[name.to_sym]
          if dashboard_filter
            dashboard_filter.arity == 1 ? dashboard_filter.call(scope) : dashboard_filter.call(scope, value)
          elsif valid_columns.include?(name.to_s)
            scope.where(name.to_s => value)
          else
            scope
          end
        end

        def self.dashboard_collection_filters(dashboard_class)
          return {} unless dashboard_class.const_defined?(:COLLECTION_FILTERS)

          dashboard_class.const_get(:COLLECTION_FILTERS)
        end

        def self.apply_search(scope, dashboard, query)
          results = FastSearch.new(scope, dashboard, query).run
          return results if results.exists?

          Administrate::Search.new(scope, dashboard, query).run
        end

        def self.apply_sort(scope, dashboard, sort, direction)
          return scope if sort.blank?

          reject_unknown!('sort fields', sort, dashboard.show_page_attributes)

          safe_direction = direction.to_s == 'asc' ? :asc : :desc
          scope.order(sort.to_sym => safe_direction)
        end
      end
    end
  end
end
