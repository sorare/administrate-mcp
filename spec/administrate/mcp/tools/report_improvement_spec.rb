# frozen_string_literal: true

RSpec.describe Administrate::MCP::Tools::ReportImprovement do
  let(:admin) { create(:admin, role: 'viewer') }

  it 'is named report_mcp_improvement so existing clients keep working' do
    expect(described_class.name_value).to eq('report_mcp_improvement')
  end

  it 'creates the feedback for any authenticated admin' do
    result = nil

    expect do
      result = described_class.call(server_context: { admin: }, category: 'description', suggestion: 'Unclear')
    end.to change(Administrate::MCP::Feedback, :count).by(1)

    body = JSON.parse(result.content.first[:text])
    expect(body).to include('status' => 'created')
    expect(body['feedback_id']).to eq(Administrate::MCP::Feedback.last.id)
  end

  it 'reports a validation failure as an error response' do
    result = described_class.call(server_context: { admin: }, category: 'nope', suggestion: 'Unclear')

    expect(result.content.first[:text]).to include('category must be one of')
  end

  it 'omits feedback_id when persist_feedback is off' do
    Administrate::MCP.config.persist_feedback = false

    result = described_class.call(server_context: { admin: }, category: 'description', suggestion: 'Unclear')

    expect(JSON.parse(result.content.first[:text])).to eq('status' => 'created')
  end
end
