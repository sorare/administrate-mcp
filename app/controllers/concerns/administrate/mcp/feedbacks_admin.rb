# frozen_string_literal: true

module Administrate
  module MCP
    # Administrate console for the improvement reports `report_mcp_improvement` stores. Reading them
    # is the whole point, so no action is overridden beyond the resource wiring and the ordering:
    # the newest report is the one a maintainer has not acted on yet.
    #
    # Only meaningful with `config.persist_feedback` on; without it nothing writes to the table.
    module FeedbacksAdmin
      extend ActiveSupport::Concern
      include ResourceController

      included do
        administrate_mcp_resource Administrate::MCP::Feedback
      end

      private

      def scoped_resource
        super.order(created_at: :desc)
      end
    end
  end
end
