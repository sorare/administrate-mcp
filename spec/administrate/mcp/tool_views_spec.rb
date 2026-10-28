# frozen_string_literal: true

RSpec.describe 'Tool views' do
  let(:admin) { create(:admin, :full_access) }
  let(:server_context) { { admin:, scopes: ['write'] } }
  let(:resource_uri) { 'ui://dummy-admin/resource' }

  def build_server
    Administrate::MCP::ServerBuilder.build(server_context:)
  end

  def listed_tool(server, name)
    server.handle({ jsonrpc: '2.0', id: 1, method: 'tools/list' })
          .dig(:result, :tools)
          .find { |tool| tool[:name] == name }
  end

  context 'when the host has not turned them on' do
    it 'publishes no view, links no tool and declares no extension' do
      server = build_server

      expect(server.resources).to be_empty
      expect(listed_tool(server, 'admin_resource_show')).not_to have_key(:_meta)
      expect(server.capabilities).not_to have_key(:extensions)
    end

    it 'adds nothing to a tool result' do
      widget = create(:widget)
      result = Administrate::MCP::Tools::AdminResourceShow.call(server_context:, resource: 'widget', id: widget.id)

      expect(result.to_h).not_to have_key(:_meta)
    end
  end

  context 'when the host turns them on' do
    before { Administrate::MCP.config.tool_views = true }

    it 'declares the MCP Apps extension' do
      expect(build_server.capabilities[:extensions])
        .to eq('io.modelcontextprotocol/ui' => { mimeTypes: ['text/html;profile=mcp-app'] })
    end

    it 'links the list and show tools to the resource view' do
      server = build_server

      %w[admin_resource_list admin_resource_show].each do |name|
        expect(listed_tool(server, name)[:_meta]).to eq(ui: { resourceUri: resource_uri })
      end
    end

    it 'renders an mcp_action in the resource view unless it names another' do
      expect(listed_tool(build_server, 'gadget_relabel')[:_meta]).to eq(ui: { resourceUri: resource_uri })
    end

    it 'leaves a tool without a view unlinked' do
      expect(listed_tool(build_server, 'admin_resource_list_resources')).not_to have_key(:_meta)
    end

    it 'publishes each linked view once and serves it over resources/read' do
      server = build_server
      listed = server.handle({ jsonrpc: '2.0', id: 1, method: 'resources/list' }).dig(:result, :resources)
      read = server.handle({ jsonrpc: '2.0', id: 2, method: 'resources/read', params: { uri: resource_uri } })

      expect(listed.pluck(:uri)).to contain_exactly(resource_uri, 'ui://dummy-admin/sidekiq')
      expect(read.dig(:result, :contents, 0)).to include(mimeType: 'text/html;profile=mcp-app', uri: resource_uri)
      expect(read.dig(:result, :contents, 0, :text)).to include('admin_resource_show')
    end

    it 'answers an unknown view uri as not found' do
      read = build_server.handle({ jsonrpc: '2.0', id: 1, method: 'resources/read', params: { uri: 'ui://nope' } })

      expect(read.dig(:error, :code)).to eq(-32_602)
    end

    it 'describes the fields of a shown record for the view' do
      widget = create(:widget)
      result = Administrate::MCP::Tools::AdminResourceShow.call(server_context:, resource: 'widget', id: widget.id)
      hints = result.to_h.dig(:_meta, 'administrate-mcp/view')

      expect(hints[:resource]).to eq('widget')
      expect(hints[:fields]).to include(
        admin: { kind: :belongs_to, resource: 'admin' },
        gadgets: { kind: :has_many, resource: 'gadget', foreign_key: 'widget_id' },
        created_at: { kind: :datetime },
        status: { kind: :enum },
        name: { kind: :scalar }
      )
      expect(hints[:fields]).not_to have_key(:secret)
    end

    it 'describes the columns of a list and of a batch show' do
      widgets = create_list(:widget, 2)
      list = Administrate::MCP::Tools::AdminResourceList.call(server_context:, resource: 'gadget')
      batch = Administrate::MCP::Tools::AdminResourceShow.call(server_context:, resource: 'widget',
                                                               id: widgets.map(&:id))
      list_fields = list.to_h.dig(:_meta, 'administrate-mcp/view', :fields)

      expect(list_fields.keys).to eq(%i[id label widget])
      expect(list_fields[:widget]).to eq(kind: :belongs_to, resource: 'widget')
      expect(batch.to_h.dig(:_meta, 'administrate-mcp/view', :fields)).to have_key(:gadgets)
    end

    it 'does not name an associated resource the caller cannot list' do
      hidden = Class.new(Administrate::MCP::Authorization::Base) do
        def authorized?(_admin, record_or_class, action)
          !(record_or_class == Admin && action == :index?)
        end
      end
      Administrate::MCP.config.authorization = hidden.new
      widget = create(:widget)
      result = Administrate::MCP::Tools::AdminResourceShow.call(server_context:, resource: 'widget', id: widget.id)
      fields = result.to_h.dig(:_meta, 'administrate-mcp/view', :fields)

      expect(fields[:admin]).to eq(kind: :belongs_to)
      expect(fields[:gadgets]).to include(resource: 'gadget')
    end

    it 'keeps the text content the model reads unchanged' do
      widget = create(:widget)
      result = Administrate::MCP::Tools::AdminResourceShow.call(server_context:, resource: 'widget', id: widget.id)

      expect(JSON.parse(result.content.first[:text])).to include('id' => widget.id, 'name' => widget.name)
      expect(result.content.size).to eq(1)
    end
  end

  describe 'a view on a host tool or an mcp_action' do
    let(:script_path) { Rails.root.join('tmp/spec_review_view.js') }
    let(:view) do
      path = script_path
      stub_const('ReviewView', Class.new(Administrate::MCP::ToolView) { script path })
    end

    before do
      Administrate::MCP.config.tool_views = true
      FileUtils.mkdir_p(File.dirname(script_path))
      File.write(script_path, '')
    end

    after { FileUtils.rm_f(script_path) }

    it 'links a host tool, with the visibility it asks for' do
      tool = Class.new(Administrate::MCP::BaseTool) { tool_name 'review_next' }
      tool.tool_view view, visibility: %i[app]

      expect(tool.to_h[:_meta]).to eq(ui: { resourceUri: 'ui://dummy-admin/review', visibility: ['app'] })
    end

    it 'resolves a view named as a string when the tool is listed' do
      view
      tool = Class.new(Administrate::MCP::BaseTool) { tool_name 'review_next' }
      tool.tool_view 'ReviewView'

      expect(tool.tool_view).to be(view)
    end

    it 'keeps meta the tool already declares' do
      tool = Class.new(Administrate::MCP::BaseTool) { tool_name 'review_next' }
      tool.meta(owner: 'reviews')
      tool.tool_view view

      expect(tool.to_h[:_meta]).to eq(owner: 'reviews', ui: { resourceUri: 'ui://dummy-admin/review' })
    end

    it 'links the tool an mcp_action declares with view:' do
      spec = Administrate::MCP::Actions.build_spec(:review, description: 'Review it.', view: 'ReviewView') { nil }
      definition = Administrate::MCP::Actions::Definition.new(model_class: Widget, **spec)
      view

      tool = Administrate::MCP::Actions::ToolFactory.build(definition)

      expect(tool.to_h.dig(:_meta, :ui, :resourceUri)).to eq('ui://dummy-admin/review')
    end
  end
end
