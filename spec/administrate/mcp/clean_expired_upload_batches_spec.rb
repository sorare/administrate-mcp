# frozen_string_literal: true

RSpec.describe Administrate::MCP::CleanExpiredUploadBatches do
  let(:admin) { create(:admin) }

  def batch(expires_at:)
    Administrate::MCP::UploadBatch.create!(admin:, expires_at:, files: [])
  end

  it 'deletes the batches that expired and keeps the others' do
    expired = batch(expires_at: 1.minute.ago)
    live = batch(expires_at: 1.hour.from_now)

    result = described_class.call

    expect(result).to have_attributes(deleted_count: 1, more?: false)
    expect(Administrate::MCP::UploadBatch.where(id: expired.id)).not_to exist
    expect(Administrate::MCP::UploadBatch.where(id: live.id)).to exist
  end

  it 'reports a full batch so the caller runs the next one' do
    stub_const("#{described_class}::BATCH_SIZE", 1)
    2.times { batch(expires_at: 1.day.ago) }

    expect(described_class.call(till: Time.current)).to have_attributes(deleted_count: 1, more?: true)
  end
end
