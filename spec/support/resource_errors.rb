# frozen_string_literal: true

# The three admin_resource tools share how they fail on a resource: an unknown name and a resource the
# caller's role cannot read are tool errors, and only a tool-level gate is recorded for the 403.
RSpec.shared_examples 'a tool reporting resource errors' do |verb:, arguments: {}|
  let(:context) { { admin: } }

  it 'returns an unknown name as a tool error with the closest registered names' do
    result = described_class.call(server_context: context, resource: 'widgit', **arguments)

    expect(result.error?).to be(true)
    expect(result.content.first[:text]).to eq(
      'Unknown resource: widgit. This name is not registered. Closest registered names: widget'
    )
    expect(context[:authorization_errors]).to be_blank
  end

  it 'suggests a namespaced name from its last segment' do
    allow(Administrate::MCP::DashboardRegistry).to receive(:resource_names).and_return(%w[shop/order widget])

    result = described_class.call(server_context: context, resource: 'order', **arguments)

    expect(result.content.first[:text]).to end_with('Closest registered names: shop/order')
  end

  it 'points to the catalog when no registered name is close' do
    result = described_class.call(server_context: context, resource: 'zorglub', **arguments)

    expect(result.content.first[:text]).to eq(
      'Unknown resource: zorglub. This name is not registered. Call admin_resource_list_resources for the catalog.'
    )
  end

  it 'returns a resource the role cannot read as a tool error that says the resource exists' do
    Administrate::MCP.config.authorization = Class.new(Administrate::MCP::Authorization::Base) do
      def authorized?(_admin, model_class, _action) = model_class != Widget
    end.new

    result = described_class.call(server_context: context, resource: 'widget', **arguments)

    expect(result.error?).to be(true)
    expect(result.content.first[:text]).to eq(
      "Resource `widget` exists but your role is not authorized to #{verb} it."
    )
    expect(context[:authorization_errors]).to be_blank
  end

  it 'still records a tool-level scope refusal for the 403' do
    allow(described_class).to receive(:required_scopes).and_return([:write])
    context[:scopes] = []

    result = described_class.call(server_context: context, resource: 'widget', **arguments)

    expect(result.error?).to be(true)
    expect(context[:authorization_errors]).to eq(['Missing required scope(s): write'])
  end
end
