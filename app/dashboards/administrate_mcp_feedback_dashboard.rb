# frozen_string_literal: true

require 'administrate/base_dashboard'

# Default Administrate dashboard for the improvement reports the feedback tool stores. A host
# that wants other columns subclasses it and redefines the constants it cares about.
class AdministrateMcpFeedbackDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::String.with_options(searchable: false),
    admin: Field::BelongsTo.with_options(class_name: Administrate::MCP.config.admin_class_name),
    api_key: Field::BelongsTo.with_options(class_name: 'Administrate::MCP::ApiKey'),
    category: Field::Select.with_options(collection: -> { Administrate::MCP::Feedback.categories.keys }),
    resource_name: Field::String,
    suggestion: Field::Text,
    status: Field::Select.with_options(collection: -> { Administrate::MCP::Feedback.statuses.keys }),
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[category resource_name status admin created_at].freeze

  SHOW_PAGE_ATTRIBUTES = %i[id admin api_key category resource_name suggestion status created_at updated_at].freeze

  # Triaging a report is the one edit worth making from the console.
  FORM_ATTRIBUTES = %i[status].freeze

  COLLECTION_FILTERS = {
    status: ->(resources, status) { resources.where(status:) },
    category: ->(resources, category) { resources.where(category:) }
  }.freeze

  def self.model
    Administrate::MCP::Feedback
  end

  def display_resource(feedback)
    "#{feedback.category} on #{feedback.resource_name.presence || 'the server'}"
  end
end
