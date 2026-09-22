# frozen_string_literal: true

RSpec.describe Administrate::MCP::ResourceResolver do
  subject(:resolver) { described_class.new('console/administrate_mcp_api_keys', resource_class:) }

  let(:resource_class) { Administrate::MCP::ApiKey }

  it 'takes the model from the controller, which cannot name a class inside the engine' do
    expect(resolver.resource_class).to eq(Administrate::MCP::ApiKey)
    expect { Administrate::ResourceResolver.new('console/administrate_mcp_api_keys').resource_class }
      .to raise_error(NameError)
  end

  it "leaves the dashboard to Administrate, because its name follows the host's inflections" do
    expect(resolver.dashboard_class).to eq(AdministrateMcpApiKeyDashboard)
  end

  it 'takes a dashboard the host names itself, for a console Administrate cannot find by name' do
    named = described_class.new(
      'console/administrate_mcp_api_keys',
      resource_class:,
      dashboard_class: WritableAdministrateMcpApiKeyDashboard
    )

    expect(named.dashboard_class).to eq(WritableAdministrateMcpApiKeyDashboard)
  end

  it 'reads parameters under the key the form builder writes them to' do
    expect(resolver.resource_name).to eq(:administrate_mcp_api_key)
  end

  it 'ships no dashboard under a name an inflection acronym would change' do
    engine_dashboards = Dir[Administrate::MCP::Engine.root.join('app/dashboards/**/*.rb')]

    expect(engine_dashboards.map { |f| f.split('app/dashboards/').last })
      .to contain_exactly('administrate/mcp/api_key_dashboard.rb', 'administrate/mcp/feedback_dashboard.rb')
  end
end
