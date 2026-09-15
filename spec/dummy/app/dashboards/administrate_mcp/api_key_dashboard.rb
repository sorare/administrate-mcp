# frozen_string_literal: true

require 'administrate/base_dashboard'

module AdministrateMcp
  # Stands for a host exposing one of the engine's own tables in its admin, which is the case the
  # namespaced model_name has to survive.
  class ApiKeyDashboard < Administrate::BaseDashboard
    MCP_DESCRIPTION = 'MCP API keys, exposed by the host admin.'

    ATTRIBUTE_TYPES = { id: Field::String, name: Field::String, admin: Field::BelongsTo }.freeze

    COLLECTION_ATTRIBUTES = %i[id name].freeze
    SHOW_PAGE_ATTRIBUTES = %i[id name admin].freeze
    FORM_ATTRIBUTES = %i[name].freeze

    def self.model
      Administrate::MCP::ApiKey
    end

    def display_resource(api_key)
      api_key.name
    end
  end
end
