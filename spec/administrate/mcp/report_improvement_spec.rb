# frozen_string_literal: true

RSpec.describe Administrate::MCP::ReportImprovement do
  subject(:result) { described_class.call(**params) }

  let(:admin) { create(:admin) }
  let!(:api_key) { create(:administrate_mcp_api_key, admin:, last_used_at: Time.current) }
  let(:params) do
    { admin:, category: 'description', suggestion: 'The description is misleading', resource_name: 'widgets' }
  end

  it 'creates the feedback record and attaches the most recently used API key' do
    expect { result }.to change(Administrate::MCP::Feedback, :count).by(1)

    expect(result).to be_success
    expect(result.feedback).to have_attributes(
      admin:,
      category: 'description',
      suggestion: 'The description is misleading',
      resource_name: 'widgets',
      api_key:
    )
  end

  it 'hands the record to the on_feedback hook' do
    seen = []
    Administrate::MCP.config.on_feedback = ->(feedback) { seen << feedback }

    expect(seen).to eq([result.feedback])
  end

  it 'still succeeds when the on_feedback hook raises' do
    Administrate::MCP.config.on_feedback = ->(_feedback) { raise 'slack is down' }

    expect(result).to be_success
    expect(result.feedback).to be_persisted
  end

  context 'with an invalid category' do
    before { params[:category] = 'invalid' }

    it 'fails without creating a record' do
      expect { result }.not_to change(Administrate::MCP::Feedback, :count)
      expect(result).not_to be_success
      expect(result.errors.first).to include('category must be one of')
    end
  end

  context 'with a blank suggestion' do
    before { params[:suggestion] = '' }

    it 'fails without creating a record' do
      expect { result }.not_to change(Administrate::MCP::Feedback, :count)
      expect(result).not_to be_success
    end
  end

  context 'when the caller authenticated over OAuth' do
    let(:params) { { admin: create(:admin), category: 'description', suggestion: 'Missing field' } }

    it 'creates the feedback without an API key' do
      expect(result).to be_success
      expect(result.feedback.api_key).to be_nil
    end
  end
end
