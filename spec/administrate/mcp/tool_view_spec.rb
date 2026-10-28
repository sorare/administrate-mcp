# frozen_string_literal: true

RSpec.describe Administrate::MCP::ToolView do
  let(:script_path) { Rails.root.join('tmp/spec_tool_view.js') }
  let(:view) do
    path = script_path
    Class.new(described_class) do
      def self.name = 'ReviewQueueView'

      script path
    end
  end

  before do
    FileUtils.mkdir_p(File.dirname(script_path))
    File.write(script_path, "AdministrateMCP.mount(AdministrateMCP.message('</script><b>hi</b>'));")
  end

  after { FileUtils.rm_f(script_path) }

  describe '.view_name and .uri' do
    it 'derives the name from the class and scopes the uri to the server name' do
      expect(view.view_name).to eq('review_queue')
      expect(view.uri).to eq('ui://dummy-admin/review_queue')
    end

    it 'takes an explicit name' do
      view.view_name 'queue'

      expect(view.uri).to eq('ui://dummy-admin/queue')
    end
  end

  describe '.contents' do
    let(:contents) { view.contents.to_h }

    it 'serves an HTML document with the MCP Apps mime type' do
      expect(contents[:uri]).to eq('ui://dummy-admin/review_queue')
      expect(contents[:mimeType]).to eq('text/html;profile=mcp-app')
      expect(contents[:text]).to start_with('<!doctype html>')
    end

    it 'inlines the shared runtime ahead of the view script' do
      text = contents[:text]

      expect(text.index('window.AdministrateMCP =')).to be < text.index('AdministrateMCP.mount(')
    end

    it 'cannot be closed early by a script that contains a closing script tag' do
      expect(contents[:text]).to include('<\/script><b>hi</b>')
      expect(contents[:text].scan('</script>').size).to eq(2)
    end

    it 'asks for a border and declares no external origin by default' do
      expect(contents[:_meta]).to eq(ui: { prefersBorder: true })
    end

    it 'declares the origins the host configured' do
      Administrate::MCP.config.tool_view_csp = { resource_domains: ['https://cdn.example.com'] }

      expect(contents.dig(:_meta, :ui, :csp)).to eq(resourceDomains: ['https://cdn.example.com'])
    end

    it 'refuses a CSP key the extension does not define' do
      Administrate::MCP.config.tool_view_csp = { script_domains: ['https://cdn.example.com'] }

      expect { view.contents }.to raise_error(ArgumentError, /script_domains/)
    end

    it 'refuses a view without a script' do
      expect { Class.new(described_class) { def self.name = 'EmptyView' }.contents }
        .to raise_error(ArgumentError, /script/)
    end
  end

  describe '.resource' do
    it 'builds a resource the server can read' do
      resource = view.resource

      expect(resource.uri).to eq(view.uri)
      expect(resource.to_h).to include(name: 'review_queue', mimeType: 'text/html;profile=mcp-app')
      expect(resource.contents(server_context: {}).text).to include('<main id="app"')
    end
  end

  describe 'the built-in views' do
    it 'ship a script and a stylesheet that exist' do
      [Administrate::MCP::ToolViews::ResourceView, Administrate::MCP::ToolViews::SidekiqView].each do |built_in|
        expect(File).to exist(built_in.script)
        expect(File).to exist(built_in.stylesheet)
        expect(built_in.document).to include('</html>')
      end
    end
  end
end
