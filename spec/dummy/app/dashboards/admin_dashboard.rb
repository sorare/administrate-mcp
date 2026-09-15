# frozen_string_literal: true

require 'administrate/base_dashboard'

class AdminDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = { id: Field::String, email: Field::String, role: Field::String }.freeze

  COLLECTION_ATTRIBUTES = %i[id email].freeze
  SHOW_PAGE_ATTRIBUTES = %i[id email role].freeze
  FORM_ATTRIBUTES = %i[email role].freeze

  def display_resource(admin)
    admin.email
  end
end
