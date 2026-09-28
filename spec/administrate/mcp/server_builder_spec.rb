# frozen_string_literal: true

RSpec.describe Administrate::MCP::ServerBuilder do
  let(:admin) { create(:admin, :full_access) }

  describe '.build' do
    it 'seeds the authorization errors array in the caller context' do
      server_context = { admin:, scopes: [] }
      described_class.build(server_context:)

      expect(server_context[:authorization_errors]).to eq([])
    end

    it 'keeps an array the caller already provided' do
      errors = ['already here']
      server_context = { admin:, scopes: [], authorization_errors: errors }
      described_class.build(server_context:)

      expect(server_context[:authorization_errors]).to be(errors)
    end

    it 'names the server from the configuration' do
      server = described_class.build(server_context: { admin:, scopes: [] })

      expect(server.name).to eq('dummy_admin')
      expect(server.version).to eq('1.2.3')
    end

    it 'builds a transport that does not serve subscriptions/listen' do
      server = described_class.build(server_context: { admin:, scopes: [] })

      expect(server.transport.serves_subscriptions_listen?).to be(false)
    end
  end

  describe '.discover_tools' do
    it 'registers the dashboard tools' do
      names = described_class.discover_tools({ admin:, scopes: [] }).map(&:name_value)

      expect(names).to include('admin_resource_list', 'admin_resource_show', 'admin_resource_list_resources',
                               'report_mcp_improvement')
    end

    it 'leaves the sidekiq stats tool out without a configured provider' do
      names = described_class.discover_tools({ admin:, scopes: [] }).map(&:name_value)

      expect(names).not_to include('sidekiq_stats')
      expect(names).to include('sidekiq_retries')
    end

    it 'registers report_mcp_improvement by default' do
      names = described_class.discover_tools({ admin:, scopes: [] }).map(&:name_value)

      expect(names).to include('report_mcp_improvement')
    end

    it 'leaves report_mcp_improvement out once feedback_tool is disabled' do
      Administrate::MCP.config.feedback_tool = false

      names = described_class.discover_tools({ admin:, scopes: [] }).map(&:name_value)

      expect(names).not_to include('report_mcp_improvement')
    end

    it 'adds the generated action tools once the write scope is granted' do
      names = described_class.discover_tools({ admin:, scopes: ['write'] }).map(&:name_value)

      expect(names).to include('gadget_relabel')
    end
  end
end
