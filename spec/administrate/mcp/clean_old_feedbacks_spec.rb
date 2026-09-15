# frozen_string_literal: true

RSpec.describe Administrate::MCP::CleanOldFeedbacks do
  let!(:old_feedback) { create(:administrate_mcp_feedback, created_at: 3.months.ago) }
  let!(:recent_feedback) { create(:administrate_mcp_feedback, created_at: 1.month.ago) }

  it 'deletes feedbacks older than the cutoff' do
    expect { described_class.call }.to change(Administrate::MCP::Feedback, :count).by(-1)

    expect { old_feedback.reload }.to raise_error(ActiveRecord::RecordNotFound)
    expect(recent_feedback.reload).to be_present
  end

  it 'reports that no further batch is needed' do
    expect(described_class.call.more?).to be(false)
  end

  context 'when the batch fills up' do
    before do
      stub_const('Administrate::MCP::CleanOldFeedbacks::BATCH_SIZE', 1)
      create(:administrate_mcp_feedback, created_at: 3.months.ago)
    end

    it 'reports that another batch is needed' do
      expect(described_class.call.more?).to be(true)
    end
  end
end
