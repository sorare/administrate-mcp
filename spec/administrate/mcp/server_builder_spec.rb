# frozen_string_literal: true

RSpec.describe Administrate::MCP::ServerBuilder do
  let(:admin) { create(:admin, :full_access) }
  let(:skills_root) { File.expand_path('../../fixtures/skills', __dir__) }

  describe '.build' do
    it 'seeds the authorization errors array in the caller context' do
      server_context = { admin:, scopes: [] }
      described_class.build(server_context:)

      expect(server_context[:authorization_errors]).to eq([])
    end

    it 'keeps an array the caller already provided' do
      errors = ['already here']
      server_context = { admin:, scopes: [], authorization_errors: errors }
      described_class.build(server_context:)

      expect(server_context[:authorization_errors]).to be(errors)
    end

    it 'names the server from the configuration' do
      server = described_class.build(server_context: { admin:, scopes: [] })

      expect(server.name).to eq('dummy_admin')
      expect(server.version).to eq('1.2.3')
    end

    it 'serves no skills by default' do
      server = described_class.build(server_context: { admin:, scopes: [] })

      expect(server.skills).to be_nil
    end

    it 'serves the skills found under skill_paths, with their files' do
      Administrate::MCP.config.skill_paths = [skills_root]
      server = described_class.build(server_context: { admin:, scopes: [] })

      expect(server.skills.map(&:name)).to eq(%w[greeting write-guide])
      expect(server.skills.first.to_h[:resources].pluck(:uri)).to include('skill://greeting/references/tone.md')
    end

    it 'serves only the skills skill_visible accepts for the request' do
      Administrate::MCP.config.skill_paths = [skills_root]
      Administrate::MCP.config.skill_visible = lambda do |skill, server_context|
        skill.name != 'write-guide' || server_context[:scopes].include?('write')
      end

      reader = described_class.build(server_context: { admin:, scopes: [] })
      writer = described_class.build(server_context: { admin:, scopes: ['write'] })

      expect(reader.skills.map(&:name)).to eq(%w[greeting])
      expect(writer.skills.map(&:name)).to eq(%w[greeting write-guide])
    end

    it 'builds a transport that does not serve subscriptions/listen' do
      server = described_class.build(server_context: { admin:, scopes: [] })

      expect(server.transport.serves_subscriptions_listen?).to be(false)
    end
  end

  describe '.discover_tools' do
    it 'registers the dashboard tools' do
      names = described_class.discover_tools({ admin:, scopes: [] }).map(&:name_value)

      expect(names).to include('admin_resource_list', 'admin_resource_show', 'admin_resource_list_resources',
                               'report_mcp_improvement')
    end

    it 'leaves the sidekiq stats tool out without a configured provider' do
      names = described_class.discover_tools({ admin:, scopes: [] }).map(&:name_value)

      expect(names).not_to include('sidekiq_stats')
      expect(names).to include('sidekiq_retries')
    end

    it 'registers report_mcp_improvement by default' do
      names = described_class.discover_tools({ admin:, scopes: [] }).map(&:name_value)

      expect(names).to include('report_mcp_improvement')
    end

    it 'leaves report_mcp_improvement out once feedback_tool is disabled' do
      Administrate::MCP.config.feedback_tool = false

      names = described_class.discover_tools({ admin:, scopes: [] }).map(&:name_value)

      expect(names).not_to include('report_mcp_improvement')
    end

    it 'adds the generated action tools once the write scope is granted' do
      names = described_class.discover_tools({ admin:, scopes: ['write'] }).map(&:name_value)

      expect(names).to include('gadget_relabel')
    end
  end
end
