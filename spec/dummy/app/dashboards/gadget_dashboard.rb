# frozen_string_literal: true

require 'administrate/base_dashboard'

class GadgetDashboard < Administrate::BaseDashboard
  MCP_DESCRIPTION = 'Gadgets belong to a widget.'

  ATTRIBUTE_TYPES = { id: Field::String, label: Field::String, widget: Field::BelongsTo }.freeze

  COLLECTION_ATTRIBUTES = %i[id label widget].freeze
  SHOW_PAGE_ATTRIBUTES = %i[id label widget].freeze
  FORM_ATTRIBUTES = %i[label].freeze

  mcp_action :relabel,
             description: 'Rename a gadget.',
             params: {
               label: {
                 type: 'string',
                 description: 'The new label.'
               }
             } do |record:, admin:, params:|
    record.update!(label: params[:label])
  end

  def display_resource(gadget)
    gadget.label
  end
end
