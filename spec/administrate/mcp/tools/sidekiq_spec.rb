# frozen_string_literal: true

RSpec.describe 'the Sidekiq tools' do
  let(:admin) { create(:admin, :full_access) }
  let(:server_context) { { admin: } }

  describe Administrate::MCP::Tools::SidekiqRetries do
    let(:retry_set) { instance_double(Sidekiq::RetrySet, size: 2, first: []) }

    before { allow(Sidekiq::RetrySet).to receive(:new).and_return(retry_set) }

    it 'returns the retry queue size' do
      data = JSON.parse(described_class.call(server_context:).content.first[:text])

      expect(data).to eq('total_size' => 2)
    end

    it 'returns the entries when asked' do
      data = JSON.parse(described_class.call(include_entries: true, server_context:).content.first[:text])

      expect(data).to eq('total_size' => 2, 'entries' => [])
    end
  end

  describe Administrate::MCP::Tools::SidekiqStats do
    let(:provider) do
      Class.new do
        def self.counts(queue) = queue == 'retries' ? { 'AJob' => 3, 'BJob' => 7 } : { 'CJob' => 1 }

        def self.total_counts(counts) = counts.values.sum

        def self.queues = %w[default mailers]

        def self.stats_cleared_at = Time.utc(2026, 1, 1)
      end
    end

    before { Administrate::MCP.config.sidekiq_stats_provider = provider }

    context 'when the provider is configured indirectly' do
      after { Administrate::MCP.config.sidekiq_stats_provider = provider }

      it 'resolves a class name lazily' do
        stub_const('HostStatsProvider', provider)
        Administrate::MCP.config.sidekiq_stats_provider = 'HostStatsProvider'

        expect(described_class.provider).to eq(provider)
      end

      it 'calls a proc' do
        Administrate::MCP.config.sidekiq_stats_provider = -> { provider }

        expect(described_class.provider).to eq(provider)
      end
    end

    it 'returns the retry breakdown sorted by count' do
      data = JSON.parse(described_class.call(server_context:).content.first[:text])

      expect(data['retries'].keys).to eq(%w[BJob AJob])
      expect(data['total_retries']).to eq(10)
      expect(data).not_to have_key('queues')
    end

    it 'returns the per-queue breakdowns when asked' do
      data = JSON.parse(described_class.call(include_queues: true, server_context:).content.first[:text])

      expect(data['queues'].keys).to eq(%w[default mailers])
    end

    it 'returns a single queue breakdown when named' do
      data = JSON.parse(
        described_class.call(include_queues: true, queue_name: 'default', server_context:).content.first[:text]
      )

      expect(data['queues'].keys).to eq(['default'])
    end
  end
end
