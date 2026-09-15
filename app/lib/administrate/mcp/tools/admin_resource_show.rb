# frozen_string_literal: true

module Administrate
  module MCP
    module Tools
      # Shows a single admin resource by ID or slug using its Administrate dashboard definition.
      class AdminResourceShow < AdminDashboardTool
        MAX_BATCH = 10
        MAX_EXPAND = 2

        def self.policy_action
          :show?
        end

        tool_name 'admin_resource_show'
        description 'Show admin resource(s) by ID or slug. ' \
                      'Accepts a single ID or an array of up to 10 IDs for batch lookup.'
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
            id: {
              oneOf: [
                { type: 'string', description: 'Single resource ID or slug — one id, never a list encoded as text' },
                {
                  type: 'array',
                  items: {
                    type: 'string'
                  },
                  maxItems: MAX_BATCH,
                  description:
                    "Multiple IDs (max #{MAX_BATCH}), as a real JSON array. A stringified array is read as one " \
                      'id, matches nothing, and fails with "<Resource> not found for: [...]" echoing the whole ' \
                      'list — that error means the ids never reached the batch path, not that they are wrong, ' \
                      'so re-send them as an array rather than falling back to single calls. ' \
                      'Attributes a dashboard computes per record are not resolved in batch mode and come back ' \
                      'as "[error: could not serialize <field>]" — pass a single ID when you need one of those.'
                }
              ]
            },
            fields: {
              type: 'array',
              items: {
                type: 'string'
              },
              description: 'Specific fields to return (optional). Returns all fields if omitted.'
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
            }
          },
          required: %w[resource id]
        )

        def self.execute(admin:, resource:, id:, fields: nil, expand: nil) # rubocop:disable Lint/UnusedMethodArgument
          entry = find_dashboard_entry!(resource)
          dashboard = entry.dashboard_class.new
          attrs, expand_set =
            resolve_attributes_and_expansions(dashboard, fields, expand, :show_page_attributes, MAX_EXPAND)

          return batch_show(entry, dashboard, id, attrs, expand_set, resource) if id.is_a?(Array)

          record = find_record(entry, id)
          return error_response("#{resource.capitalize} not found for: #{id}") unless record

          json_response(
            FieldSerializer.serialize(record, dashboard, attributes: attrs, expand: expand_set, resolve_getters: true)
          )
        end

        # Getters stay unresolved here: they are per-record work, and a batch multiplies them by up
        # to MAX_BATCH. Read one id at a time when a getter-backed attribute matters.
        def self.batch_show(entry, dashboard, ids, attrs, expand_set, resource)
          reject_over_limit!('ids', ids.size, MAX_BATCH)
          columns = FieldSerializer.resolve_columns(dashboard, attrs)

          rows =
            ids.map do |single_id|
              record = find_record(entry, single_id)
              if record
                [FieldSerializer.admin_url_for(record)] +
                  FieldSerializer.serialize_row(record, dashboard, columns:, expand: expand_set)
              else
                { id: single_id, error: "#{resource.capitalize} not found" }
              end
            end

          json_response({ columns: %w[url] + columns.map(&:to_s), rows: })
        end

        def self.find_record(entry, id)
          entry.scope.find_by(id:) || friendly_find(entry, id)
        rescue ActiveRecord::RecordNotFound
          nil
        end

        def self.friendly_find(entry, id)
          return nil unless entry.model_class.respond_to?(:friendly)

          entry.scope.friendly.find(id)
        rescue ActiveRecord::RecordNotFound
          nil
        end
      end
    end
  end
end
