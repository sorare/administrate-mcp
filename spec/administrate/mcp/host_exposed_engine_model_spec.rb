# frozen_string_literal: true

RSpec.describe 'a host that exposes an engine table in its own admin' do
  let(:admin) { create(:admin, :full_access) }
  let!(:api_key) { create(:administrate_mcp_api_key, admin:) }

  it 'is registered under the namespaced model name' do
    entry = Administrate::MCP::DashboardRegistry.find('administrate/mcp/api_key')

    expect(entry.model_class).to eq(Administrate::MCP::ApiKey)
    expect(entry.dashboard_class).to eq(AdministrateMcp::ApiKeyDashboard)
  end

  it 'builds the admin URL from the namespaced route key' do
    result = Administrate::MCP::Tools::AdminResourceShow.call(
      server_context: { admin: },
      resource: 'administrate/mcp/api_key',
      id: api_key.id
    )
    data = JSON.parse(result.content.first[:text])

    expect(data['url']).to eq("https://admin.example.com/admin/administrate_mcp_api_keys/#{api_key.id}")
    expect(data['name']).to eq(api_key.name)
  end
end
