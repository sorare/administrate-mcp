# frozen_string_literal: true

# A client must never be able to stand in for the authenticated admin: a `tools/call` carrying an
# `admin` argument is refused before the tool runs.
RSpec.describe 'Reserved tool arguments' do
  let(:admin) { create(:admin, :full_access) }
  let(:server) { Administrate::MCP::ServerBuilder.build(server_context: { admin:, scopes: ['write'] }) }

  def call_tool(name, arguments)
    server.handle({ jsonrpc: '2.0', id: 1, method: 'tools/call', params: { name:, arguments: } })
  end

  context 'with a built-in tool' do
    let(:tool) { Administrate::MCP::Tools::AdminResourceListResources }

    it 'refuses a forged admin before execute runs' do
      allow(tool).to receive(:execute).and_call_original

      response = call_tool('admin_resource_list_resources', { admin: 'forged' })

      expect(response.dig(:result, :isError)).to be(true)
      expect(response.dig(:result, :content, 0, :text)).to include('Reserved argument(s)', 'admin')
      expect(tool).not_to have_received(:execute)
    end

    it 'audits the refused call under the authenticated admin' do
      seen = []
      Administrate::MCP.config.on_tool_call = ->(**args) { seen << args }

      call_tool('admin_resource_list_resources', { admin: 'forged' })

      expect(seen).to contain_exactly(include(admin:, arguments: { admin: 'forged' }))
    end

    it 'still runs a call without the reserved argument' do
      allow(tool).to receive(:execute).and_call_original

      response = call_tool('admin_resource_list_resources', {})

      expect(response.dig(:result, :isError)).to be_falsey
      expect(tool).to have_received(:execute).with(admin:)
    end
  end

  context 'with a host-defined tool' do
    let(:tool) do
      Class.new(Administrate::MCP::BaseTool) do
        tool_name 'host_echo'
        description 'Echoes the caller'
        input_schema(properties: { msg: { type: 'string' } })

        def self.execute(admin:, msg: nil)
          text_response("#{admin.id} #{msg}")
        end
      end
    end
    let(:server) { MCP::Server.new(name: 'host', tools: [tool], server_context: { admin: }) }

    it 'refuses a forged admin before execute runs' do
      allow(tool).to receive(:execute).and_call_original

      response = call_tool('host_echo', { msg: 'hi', admin: 'forged' })

      expect(response.dig(:result, :isError)).to be(true)
      expect(tool).not_to have_received(:execute)
    end

    it 'refuses to declare a reserved input property' do
      expect { Class.new(Administrate::MCP::BaseTool) { input_schema(properties: { admin: { type: 'string' } }) } }
        .to raise_error(ArgumentError, /reserved input property name\(s\): admin/)
    end
  end

  context 'with a dashboard action' do
    let(:gadget) { create(:gadget, label: 'Original') }

    after { Administrate::MCP::Actions.reset! }

    it 'refuses a forged admin before the action block runs' do
      allow(Administrate::MCP::Actions::ToolFactory).to receive(:invoke).and_call_original

      response = call_tool('gadget_relabel', { id: gadget.id, label: 'Renamed', admin: 'forged' })

      expect(response.dig(:result, :isError)).to be(true)
      expect(Administrate::MCP::Actions::ToolFactory).not_to have_received(:invoke)
      expect(gadget.reload.label).to eq('Original')
    end

    it 'refuses a forged admin even when the arguments skip schema validation' do
      tool = Administrate::MCP::Actions.tools_for({ admin:, scopes: ['write'] }).first
      allow(Administrate::MCP::Actions::ToolFactory).to receive(:invoke).and_call_original

      server_context = { admin:, scopes: ['write'] }
      result = tool.call(id: gadget.id, label: 'Renamed', admin: 'forged', server_context:)

      expect(result.content.first[:text]).to include('Reserved argument(s)')
      expect(Administrate::MCP::Actions::ToolFactory).not_to have_received(:invoke)
      expect(gadget.reload.label).to eq('Original')
    end

    it 'passes the authenticated admin to the action block' do
      allow(Administrate::MCP::Actions::ToolFactory).to receive(:invoke).and_call_original

      response = call_tool('gadget_relabel', { id: gadget.id, label: 'Renamed' })

      expect(response.dig(:result, :isError)).to be_falsey
      expect(Administrate::MCP::Actions::ToolFactory)
        .to have_received(:invoke).with(anything, admin, gadget.id, { label: 'Renamed' })
      expect(gadget.reload.label).to eq('Renamed')
    end
  end
end
