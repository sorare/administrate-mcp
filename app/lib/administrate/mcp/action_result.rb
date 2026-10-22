# frozen_string_literal: true

module Administrate
  module MCP
    # What an `mcp_action` block may return to send data back to the client. `record` goes through
    # the same checks as a record returned directly, and gives a collection action its `id`; `data`
    # is answered as `mcp_data`, which the engine adds to the response under `data`, or to the error
    # of a failure. Any result object that answers `mcp_data` works the same way.
    class ActionResult
      attr_reader :record, :data, :error

      alias mcp_data data

      private_class_method :new

      def self.success(record: nil, data: nil)
        new(record:, data:, error: nil, success: true)
      end

      def self.failure(error = nil, data: nil)
        new(record: nil, data:, error:, success: false)
      end

      def initialize(record:, data:, error:, success:)
        @record = record
        @data = data
        @error = error
        @success = success
      end

      def success?
        @success
      end
    end
  end
end
