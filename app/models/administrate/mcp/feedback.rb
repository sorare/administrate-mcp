# frozen_string_literal: true

module Administrate
  module MCP
    # Improvement feedback submitted by MCP users.
    class Feedback < ApplicationRecord
      self.table_name = 'administrate_mcp_feedbacks'

      belongs_to_admin
      belongs_to :api_key, class_name: 'Administrate::MCP::ApiKey', optional: true, inverse_of: :feedbacks

      enum :category,
           { description: 0, missing_filter: 1, missing_field: 2, missing_resource: 3, serialization: 4, other: 5 }
      enum :status, { pending: 0, accepted: 1, rejected: 2, shipped: 3 }, prefix: true

      validates :suggestion, presence: true
      validates :category, presence: true
    end
  end
end
