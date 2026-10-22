# frozen_string_literal: true

module Administrate
  module MCP
    # What an `mcp_action` block may return to send data back to the client. `record` goes through
    # the same checks as a record returned directly, and gives a collection action its `id`; `data`
    # is answered as `mcp_data`, which the engine adds to the response under `data`, or to the error
    # of a failure. Any result object that answers `mcp_data` works the same way.
    class Result
      attr_reader :record, :data, :error

      alias mcp_data data

      def self.success(record: nil, data: nil)
        new(record:, data:)
      end

      def self.failure(error = nil, data: nil)
        new(error:, data:, success: false)
      end

      def initialize(record: nil, data: nil, error: nil, success: true)
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
