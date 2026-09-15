# frozen_string_literal: true

module Administrate
  module MCP
    module Tools
      # Lets MCP users report improvements (misleading descriptions, missing filters, etc.).
      # Open to every authenticated admin: reporting a bad description is not a privileged action.
      class ReportImprovement < BaseTool
        tool_name 'report_mcp_improvement'
        requires_roles
        description 'Report an improvement for the MCP server (misleading description, missing filter, ' \
                    'bad serialization, missing resource, etc.).'

        input_schema(
          properties: {
            category: {
              type: 'string',
              enum: Feedback.categories.keys,
              description: 'The type of improvement being reported.'
            },
            resource_name: {
              type: 'string',
              description: 'The resource this feedback relates to (optional).'
            },
            suggestion: {
              type: 'string',
              description: 'A detailed description of the improvement.'
            }
          },
          required: %w[category suggestion]
        )

        def self.execute(admin:, category:, suggestion:, resource_name: nil)
          result = Administrate::MCP::ReportImprovement.call(admin:, category:, suggestion:, resource_name:)

          return error_response(result.errors.join(', ')) unless result.success?

          json_response({ status: 'created', feedback_id: result.feedback.id })
        end
      end
    end
  end
end
