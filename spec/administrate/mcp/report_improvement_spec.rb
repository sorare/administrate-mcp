# frozen_string_literal: true

RSpec.describe Administrate::MCP::ReportImprovement do
  subject(:result) { described_class.call(**params) }

  let(:admin) { create(:admin) }
  let!(:api_key) { create(:administrate_mcp_api_key, admin:, last_used_at: Time.current) }
  let(:params) do
    { admin:, category: 'description', suggestion: 'The description is misleading', resource_name: 'widgets' }
  end

  shared_examples 'validates the report the same way regardless of persistence' do
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
        expect(result.errors).to include("suggestion can't be blank")
      end
    end
  end

  context 'when persist_feedback is on' do
    it 'creates the feedback record and attaches the most recently used API key' do
      expect { result }.to change(Administrate::MCP::Feedback, :count).by(1)

      expect(result).to be_success
      expect(result.report.record).to have_attributes(
        admin:,
        category: 'description',
        suggestion: 'The description is misleading',
        resource_name: 'widgets',
        api_key:
      )
      expect(result.report.api_key).to eq(api_key)
    end

    it 'hands the report to the on_feedback hook, carrying the persisted record' do
      seen = []
      Administrate::MCP.config.on_feedback = ->(report) { seen << report }

      expect(seen).to eq([result.report])
      expect(seen.first.record).to be_persisted
    end

    it 'still succeeds when the on_feedback hook raises, and reports the exception' do
      reported = []
      Administrate::MCP.config.on_feedback = ->(_report) { raise 'slack is down' }
      Administrate::MCP.config.on_error = ->(exception) { reported << exception }

      expect(result).to be_success
      expect(result.report.record).to be_persisted
      expect(reported.first.message).to eq('slack is down')
    end

    context 'when the caller authenticated over OAuth' do
      let(:params) { { admin: create(:admin), category: 'description', suggestion: 'Missing field' } }

      it 'creates the feedback without an API key' do
        expect(result).to be_success
        expect(result.report.record.api_key).to be_nil
        expect(result.report.api_key).to be_nil
      end
    end

    it_behaves_like 'validates the report the same way regardless of persistence'
  end

  context 'when persist_feedback is off' do
    before { Administrate::MCP.config.persist_feedback = false }

    it 'does not create a feedback record' do
      expect { result }.not_to change(Administrate::MCP::Feedback, :count)
    end

    it 'does not look up an API key' do
      allow(Administrate::MCP::ApiKey).to receive(:active).and_call_original

      result

      expect(Administrate::MCP::ApiKey).not_to have_received(:active)
    end

    it 'succeeds and hands a report with no record or api_key to the on_feedback hook' do
      seen = []
      Administrate::MCP.config.on_feedback = ->(report) { seen << report }

      expect(result).to be_success
      expect(result.report.record).to be_nil
      expect(result.report.api_key).to be_nil
      expect(result.report).to have_attributes(
        admin:,
        category: 'description',
        suggestion: 'The description is misleading',
        resource_name: 'widgets'
      )
      expect(seen).to eq([result.report])
    end

    it_behaves_like 'validates the report the same way regardless of persistence'
  end
end
