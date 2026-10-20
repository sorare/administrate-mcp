# frozen_string_literal: true

RSpec.describe Administrate::MCP::Tools::UploadsPrepare do
  let(:admin) { create(:admin, :full_access) }
  let(:arguments) { { tool: 'widget_create_draft', attribute: 'picture', files: { 'logo.png': 1024 } } }

  def tool_names(scopes: ['write'])
    Administrate::MCP::ServerBuilder.discover_tools({ admin:, scopes: }).map(&:name_value)
  end

  it 'is not published until uploads are enabled' do
    expect(tool_names).not_to include('uploads_prepare')
  end

  context 'with uploads enabled' do
    include_context 'with presignable storage'

    it 'is published to a caller with an action that accepts uploads' do
      expect(tool_names).to include('uploads_prepare')
    end

    it 'works out the caller\'s action tools once per server build' do
      allow(Administrate::MCP::Actions).to receive(:tools_for).and_call_original

      tool_names

      expect(Administrate::MCP::Actions).to have_received(:tools_for).once
    end

    it 'is not published to a caller without such an action' do
      Administrate::MCP.config.authorization = Class.new(Administrate::MCP::Authorization::Base) do
        def authorized?(_admin, _record_or_class, action) = action != :create?
      end.new

      expect(tool_names).not_to include('uploads_prepare')
    end

    it 'returns an upload per file' do
      result = described_class.call(**arguments, server_context: { admin:, scopes: ['write'] })

      body = JSON.parse(result.content.first[:text])
      expect(body['logo.png']).to include('upload_id', 'url', 'method' => 'POST')
      expect(body['logo.png']['fields']).to include('Content-Type' => 'image/png')
    end

    it 'accepts a file as a size and checksum' do
      files = { 'logo.png': { size: 1024, checksum: Digest::MD5.base64digest('logo') } }
      result = described_class.call(**arguments, files:, server_context: { admin:, scopes: ['write'] })

      expect(result.error?).to be(false)
      expect(JSON.parse(result.content.first[:text])['logo.png']).to include('method' => 'POST')
    end

    it 'requires the write scope' do
      result = described_class.call(**arguments, server_context: { admin:, scopes: [] })

      expect(result.content.first[:text]).to eq('Missing required scope(s): write')
      expect(Administrate::MCP::UploadBatch.count).to eq(0)
    end

    it 'reports a rejected file as a tool error' do
      result = described_class.call(**arguments, files: { 'notes.pdf': 10 },
                                                 server_context: { admin:, scopes: ['write'] })

      expect(result.error?).to be(true)
      expect(result.content.first[:text]).to include('notes.pdf is not an allowed file type')
    end
  end
end
