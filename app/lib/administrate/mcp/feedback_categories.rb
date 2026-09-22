# frozen_string_literal: true

module Administrate
  module MCP
    # The category list behind `Feedback#category` and the `report_mcp_improvement` schema, kept
    # independent of the model so validation and the tool's input schema work whether or not the
    # `administrate_mcp_feedbacks` table exists.
    module FeedbackCategories
      CATEGORIES = {
        'description' => 0,
        'missing_filter' => 1,
        'missing_field' => 2,
        'missing_resource' => 3,
        'serialization' => 4,
        'other' => 5
      }.freeze
    end
  end
end
