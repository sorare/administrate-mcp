# frozen_string_literal: true

require 'administrate/base_dashboard'

module Administrate
  module MCP
    # Default Administrate dashboard for the engine's API keys. A host that wants other columns
    # subclasses it and redefines the constants it cares about.
    #
    # Nothing here is registered as an MCP resource: the registry only reads the host's own
    # dashboard directory, so a host that wants the keys listed over the protocol declares a
    # subclass there with an `MCP_DESCRIPTION`.
    class ApiKeyDashboard < Administrate::BaseDashboard
      ATTRIBUTE_TYPES = {
        id: Field::String.with_options(searchable: false),
        admin: Field::BelongsTo.with_options(class_name: Administrate::MCP.config.admin_class_name),
        name: Field::String,
        token_prefix: Field::String,
        write_access: Field::Boolean,
        last_used_at: Field::DateTime,
        revoked_at: Field::DateTime,
        created_at: Field::DateTime,
        updated_at: Field::DateTime
      }.freeze

      COLLECTION_ATTRIBUTES = %i[name admin token_prefix write_access last_used_at revoked_at].freeze

      SHOW_PAGE_ATTRIBUTES = %i[
        id
        admin
        name
        token_prefix
        write_access
        last_used_at
        revoked_at
        created_at
        updated_at
      ].freeze

      FORM_ATTRIBUTES = %i[name write_access].freeze

      COLLECTION_FILTERS = {}.freeze

      def self.model
        Administrate::MCP::ApiKey
      end

      def display_resource(api_key)
        "#{api_key.name} (#{api_key.token_prefix}...)"
      end
    end
  end
end
