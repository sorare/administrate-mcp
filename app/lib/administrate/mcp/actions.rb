# frozen_string_literal: true

module Administrate
  module MCP
    # Generates self-describing MCP tools from the custom write actions declared on dashboards.
    #
    # A dashboard declares an action with `mcp_action`, alongside its MCP_DESCRIPTION — so one file
    # defines a resource's full MCP contract (readable fields + writable actions). From each
    # declaration we build a tool whose name, input schema and description let non-developer users
    # discover and call it through the protocol.
    #
    # An action is a member action by default: it takes an `id` and runs against the loaded record.
    # Declared with `on: :collection`, it takes no `id`, loads nothing and runs against the model.
    #
    # An action declared with `uploads:` (true, a list of attachment attributes, or a hash of
    # attribute to `content_types:` / `max_size:` overrides) also takes an optional
    # `<attribute>_upload_id` for each of them. The id is resolved into the attachment value before
    # the block runs, so the block sees `params[:<attribute>]`.
    #
    # Enforcement is layered: the generated tool requires an OAuth `write` scope (the rollout gate)
    # AND runs the resource's authorization predicate against the loaded record, or against a new
    # instance of the model for a collection action, as Administrate does for `new` and `create`.
    # Auditing is inherited from BaseTool.
    module Actions
      Definition =
        Struct.new(
          :model_class,
          :name,
          :on,
          :predicate,
          :scope,
          :destructive,
          :description,
          :params,
          :required,
          :uploads,
          :invoke,
          keyword_init: true
        )

      RESERVED_PARAMS = %i[admin id].freeze

      TARGETS = %i[member collection].freeze

      class << self
        # Normalizes the arguments of a `mcp_action` declaration into a spec (everything but the
        # model, which is inferred from the owning dashboard when definitions are built).
        def build_spec(name, description:, on: :member, params: {}, predicate: nil, pundit: nil, scope: :write,
                       destructive: true, uploads: false, &invoke)
          raise ArgumentError, "#{name}: a block is required to invoke the action" unless invoke
          raise ArgumentError, "#{name}: on: must be :member or :collection" unless TARGETS.include?(on)

          reject_reserved_params!(name, params)
          normalized = normalize_params(params)

          {
            name: name.to_sym,
            on:,
            predicate: (predicate || pundit || :"#{name}?").to_sym,
            scope: scope.to_sym,
            destructive:,
            description:,
            params: normalized.transform_values { |spec| spec.except(:required) },
            required: normalized.reject { |_, spec| spec[:required] == false }.keys,
            uploads: Uploads::Declarations.normalize(uploads, action_name: name),
            invoke:
          }
        end

        def normalize_params(params)
          params.to_h do |name, spec|
            [name.to_sym, spec.is_a?(String) ? { type: 'string', description: spec } : spec.to_h.symbolize_keys]
          end
        end

        def definitions
          @definitions ||=
            DashboardRegistry.registry.values.flat_map do |entry|
              next [] unless entry.dashboard_class.respond_to?(:mcp_action_specs)

              entry.dashboard_class.mcp_action_specs.map do |spec|
                uploads = Uploads::Declarations.action_attributes(entry.dashboard_class, spec[:name], spec[:uploads])
                Definition.new(model_class: entry.model_class, **spec, uploads:)
              end
            end
        end

        def tool_name(definition)
          "#{definition.model_class.name.underscore.tr('/', '_')}_#{definition.name}"
        end

        def available_to?(admin, definition, scopes:)
          scopes.map(&:to_sym).include?(definition.scope) && authorized_for_discovery?(admin, definition)
        end

        def all_tools
          @all_tools ||= definitions.map { |defn| ToolFactory.build(defn) }
        end

        # Tool classes the caller may both see and run: write scope granted AND the authorization
        # predicate satisfied at the role level. The actual call re-checks it against the record.
        def tools_for(server_context)
          scopes = server_context[:scopes] || []
          all_tools.select { |tool| available_to?(server_context[:admin], tool.definition, scopes:) }
        end

        def reset!
          @definitions = nil
          @all_tools = nil
        end

        def find_record!(model_class, id)
          record = model_class.find_by(id:) || friendly_find(model_class, id)
          raise UnauthorizedError, "#{model_class.name} not found: #{id}" unless record

          record
        end

        def authorize!(admin, record, predicate)
          Administrate::MCP.config.authorization.authorize!(admin, record, predicate)
        end

        private

        def reject_reserved_params!(name, params)
          reserved = RESERVED_PARAMS & params.keys.map(&:to_sym)
          raise ArgumentError, "#{name}: reserved param name(s): #{reserved.join(', ')}" if reserved.any?
        end

        def authorized_for_discovery?(admin, definition)
          target = definition.on == :collection ? definition.model_class.new : definition.model_class
          Administrate::MCP.config.authorization.authorized?(admin, target, definition.predicate)
        rescue StandardError
          false
        end

        def friendly_find(model_class, id)
          return nil unless model_class.respond_to?(:friendly)

          model_class.friendly.find(id)
        rescue ActiveRecord::RecordNotFound
          nil
        end
      end

      # Turns one Definition into an anonymous BaseTool subclass.
      module ToolFactory
        class << self
          def build(defn)
            resource = defn.model_class.name.underscore
            klass = Class.new(BaseTool)
            klass.tool_name Actions.tool_name(defn)
            klass.description defn.description
            klass.annotations(read_only_hint: false, destructive_hint: defn.destructive, open_world_hint: true)
            klass.requires_scope defn.scope
            klass.input_schema(**schema_for(defn, resource))
            define_behaviors(klass, defn)
            klass
          end

          private

          def schema_for(defn, resource)
            properties = defn.params.merge(Uploads::Declarations.param_schemas(defn))
            required = defn.required.map(&:to_s)
            if defn.on == :member
              properties = { id: { type: 'string', description: "ID or slug of the #{resource}" }, **properties }
              required = %w[id] + required
            end
            { properties:, required:, additionalProperties: false }
          end

          def define_behaviors(klass, defn)
            klass.define_singleton_method(:definition) { defn }
            klass.define_singleton_method(:check_roles!) do |admin, id: nil, **|
              ToolFactory.send(:authorize!, defn, admin, id)
            end
            klass.define_singleton_method(:execute) do |admin:, id: nil, **params|
              outcome = ToolFactory.send(:invoke, defn, admin, id, params)
              outcome.key?(:error) ? error_response(outcome[:error]) : json_response(outcome[:data])
            end
          end

          def authorize!(defn, admin, id)
            target = defn.on == :member ? Actions.find_record!(defn.model_class, id) : defn.model_class.new
            Actions.authorize!(admin, target, defn.predicate)
          end

          def invoke(defn, admin, id, params)
            declared = params.slice(*defn.params.keys, *Uploads::Declarations.param_schemas(defn).keys)
            arguments = { admin:, params: Uploads::Declarations.resolve_params(defn, admin, declared) }
            arguments[:record] = Actions.find_record!(defn.model_class, id) if defn.on == :member
            result = defn.invoke.call(**arguments)
            return { error: failure_message(defn, result, arguments[:record]) } if failed?(result)

            { data: success_data(defn, id, result) }
          end

          def success_data(defn, id, result)
            id = result.id if defn.on == :collection && result.is_a?(ActiveRecord::Base)
            { status: 'ok', model: defn.model_class.name.underscore, id:, action: defn.name.to_s }.compact
          end

          def failed?(result)
            return true if result == false
            return result.new_record? || result.errors.any? if result.is_a?(ActiveRecord::Base)

            result.respond_to?(:success?) && !result.success?
          end

          def failure_message(defn, result, record)
            invalid = result.is_a?(ActiveRecord::Base) ? result : (record if result == false)
            message = invalid ? invalid.errors.full_messages.to_sentence : result.try(:error)
            message.presence || "#{defn.name} failed"
          end
        end
      end
    end
  end
end
