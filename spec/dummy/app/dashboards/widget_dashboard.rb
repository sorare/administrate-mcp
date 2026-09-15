# frozen_string_literal: true

require 'administrate/base_dashboard'

class WidgetDashboard < Administrate::BaseDashboard
  MCP_DESCRIPTION = 'Widgets, the dummy app resource used to exercise the engine.'
  MCP_BASE_SCOPE = -> { Widget.unscope(where: :status) }

  COLLECTION_FILTERS = {
    published: ->(scope) { scope.where(status: :published) },
    named: ->(scope, value) { scope.where(name: value) }
  }.freeze

  ATTRIBUTE_TYPES = {
    id: Field::String.with_options(searchable: false),
    name: Field::String,
    slug: Field::String,
    status: Field::Select.with_options(collection: Widget.statuses.keys),
    price: Field::Number,
    featured: Field::Boolean,
    admin: Field::BelongsTo,
    gadgets: Field::HasMany,
    created_at: Field::DateTime,
    updated_at: Field::DateTime,
    secret: Field::Password
  }.freeze

  COLLECTION_ATTRIBUTES = %i[id name status].freeze
  SHOW_PAGE_ATTRIBUTES = %i[id name slug status price featured admin gadgets created_at updated_at secret].freeze
  FORM_ATTRIBUTES = %i[name status price featured].freeze
  COLLECTION_FILTERS_ORDER = [].freeze

  def display_resource(widget)
    widget.name
  end
end
