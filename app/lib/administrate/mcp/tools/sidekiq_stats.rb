# frozen_string_literal: true

module Administrate
  module MCP
    module Tools
      # Exposes the host's per-job-class Sidekiq queue stats, through `config.sidekiq_stats_provider`.
      # The provider answers `counts(queue)`, `total_counts(counts)`, `queues` and `stats_cleared_at`.
      class SidekiqStats < BaseTool
        MAX_QUEUES = 20
        RETRY_QUEUE = 'retries'

        tool_name 'sidekiq_stats'
        description 'Get per-job-class counts from the custom Sidekiq stats. ' \
                      'Returns retry breakdown and optionally per-queue breakdowns. ' \
                      'Each breakdown maps job class names to their pending count.'
        annotations read_only_hint: true, destructive_hint: false, open_world_hint: false

        input_schema(
          properties: {
            include_queues: {
              type: 'boolean',
              description: 'When true, also returns per-queue job class breakdowns (capped at 20 queues).'
            },
            queue_name: {
              type: 'string',
              description: 'Return stats for a specific queue only. Ignored when include_queues is false.'
            }
          }
        )

        def self.provider
          Administrate::MCP.config.sidekiq_stats_provider
        end

        def self.retry_queue
          provider.const_defined?(:RETRY_QUEUE) ? provider.const_get(:RETRY_QUEUE) : RETRY_QUEUE
        end

        def self.execute(admin:, include_queues: false, queue_name: nil) # rubocop:disable Lint/UnusedMethodArgument
          retries = provider.counts(retry_queue)

          data = {
            stats_cleared_at: provider.stats_cleared_at.iso8601,
            retries: sort_desc(retries),
            total_retries: provider.total_counts(retries)
          }

          data[:queues] = queue_breakdowns(queue_name) if include_queues

          json_response(data)
        end

        def self.queue_breakdowns(queue_name)
          queues = queue_name.present? ? [queue_name] : provider.queues.first(MAX_QUEUES)

          queues.to_h do |q|
            counts = provider.counts(q)
            [q, { counts: sort_desc(counts), total: provider.total_counts(counts) }]
          end
        end
        private_class_method :queue_breakdowns

        def self.sort_desc(counts)
          counts.sort_by { |_, v| -v }.to_h
        end
        private_class_method :sort_desc
      end
    end
  end
end
