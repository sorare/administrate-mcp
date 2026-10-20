# frozen_string_literal: true

RSpec.describe Administrate::MCP::Tools::UploadsPrepare do
  let(:admin) { create(:admin, :full_access) }

  def tool_names(scopes: ['write'])
    Administrate::MCP::ServerBuilder.discover_tools({ admin:, scopes: }).map(&:name_value)
  end

  it 'is not published until uploads are enabled' do
    expect(tool_names).not_to include('uploads_prepare')
  end

  context 'with uploads enabled' do
    include_context 'with presignable storage'

    it 'is published' do
      expect(tool_names).to include('uploads_prepare')
    end

    it 'returns an upload per file' do
      result = described_class.call(files: { 'logo.png': 1024 }, server_context: { admin:, scopes: ['write'] })

      body = JSON.parse(result.content.first[:text])
      expect(body['logo.png']).to include('upload_id', 'url', 'headers' => { 'Content-Type' => 'image/png' })
    end

    it 'requires the write scope' do
      result = described_class.call(files: { 'logo.png': 1024 }, server_context: { admin:, scopes: [] })

      expect(result.content.first[:text]).to eq('Missing required scope(s): write')
      expect(Administrate::MCP::UploadBatch.count).to eq(0)
    end

    it 'reports a rejected file as a tool error' do
      result = described_class.call(files: { 'notes.pdf': 10 }, server_context: { admin:, scopes: ['write'] })

      expect(result.error?).to be(true)
      expect(result.content.first[:text]).to include('notes.pdf is not an allowed file type')
    end
  end
end
