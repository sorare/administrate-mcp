# frozen_string_literal: true

module Administrate
  module MCP
    module Tools
      # Exposes Sidekiq retry queue metrics: total size and first page of retries.
      class SidekiqRetries < BaseTool
        PAGE_SIZE = 25

        tool_name 'sidekiq_retries'
        description 'Get the Sidekiq retry queue size and optionally the first page of retry entries ' \
                      '(up to 25 jobs with class, error, retry count, and timestamps).'
        annotations read_only_hint: true, destructive_hint: false, open_world_hint: false

        input_schema(
          properties: {
            include_entries: {
              type: 'boolean',
              description: 'When true, returns the first page of retry entries alongside the total count.'
            }
          }
        )

        def self.execute(admin:, include_entries: false) # rubocop:disable Lint/UnusedMethodArgument
          retry_set = ::Sidekiq::RetrySet.new
          data = { total_size: retry_set.size }

          data[:entries] = retry_set.first(PAGE_SIZE)&.map { |entry| serialize_entry(entry) } || [] if include_entries

          json_response(data)
        end

        def self.serialize_entry(entry) # rubocop:disable Metrics/AbcSize
          {
            jid: entry.jid,
            queue: entry.queue,
            class: entry['class'],
            error_class: entry['error_class'],
            error_message: entry['error_message']&.truncate(200),
            retry_count: entry['retry_count'],
            failed_at: entry['failed_at'] && Time.at(entry['failed_at']).utc.iso8601,
            retried_at: entry['retried_at'] && Time.at(entry['retried_at']).utc.iso8601,
            next_retry_at: Time.at(entry.score).utc.iso8601
          }
        end
        private_class_method :serialize_entry
      end
    end
  end
end
