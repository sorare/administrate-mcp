# frozen_string_literal: true

RSpec.describe 'Data returned by an mcp_action' do
  let(:admin) { create(:admin, :full_access) }
  let(:gadget) { create(:gadget) }
  let(:ctx) { { admin:, scopes: ['write'] } }

  after { Administrate::MCP::Actions.reset! }

  def build_tool(model: Gadget, **options, &block)
    spec = Administrate::MCP::Actions.build_spec(:fix, description: 'Fix it', **options, &block)
    definition = Administrate::MCP::Actions::Definition.new(model_class: model, **spec)
    Administrate::MCP::Actions::ToolFactory.build(definition)
  end

  def answer(result)
    JSON.parse(result.content.first[:text])
  end

  def success(...) = Administrate::MCP::ActionResult.success(...)

  def failure(...) = Administrate::MCP::ActionResult.failure(...)

  def returning(data) = Struct.new(:mcp_data).new(data)

  describe Administrate::MCP::ActionResult do
    it 'is built as a success or a failure' do
      expect(success).to have_attributes(success?: true, record: nil, data: nil)
      expect(success(record: gadget, data: { a: 1 }))
        .to have_attributes(success?: true, record: gadget, mcp_data: { a: 1 })
      expect(failure('Nope', data: { b: 2 })).to have_attributes(success?: false, error: 'Nope', mcp_data: { b: 2 })
      expect(failure).to have_attributes(success?: false, error: nil)
    end

    it 'cannot be built with new, where an error could read as a success' do
      expect { described_class.new(record: nil, data: nil, error: 'Nope', success: true) }.to raise_error(NoMethodError)
    end
  end

  context 'with a member action' do
    it 'adds the data of a Result to the response under data' do
      tool = build_tool do |record:, **|
        previous = record.label
        record.update!(label: 'Renamed')
        success(record:, data: { previous_label: previous })
      end

      result = tool.call(id: gadget.id, server_context: ctx)

      expect(answer(result)).to eq(
        'status' => 'ok', 'model' => 'gadget', 'id' => gadget.id, 'action' => 'fix',
        'data' => { 'previous_label' => gadget.label }
      )
      expect(gadget.reload.label).to eq('Renamed')
    end

    it 'adds the mcp_data of any result object that answers it' do
      report = returning({ created: 2, missing: %w[a b] })

      result = build_tool { |**| report }.call(id: gadget.id, server_context: ctx)

      expect(answer(result)).to include('status' => 'ok', 'data' => { 'created' => 2, 'missing' => %w[a b] })
    end

    it 'keeps a plain Hash out of the response, as before' do
      result = build_tool { |**| { secret: 'not for the client' } }.call(id: gadget.id, server_context: ctx)

      expect(answer(result)).to eq('status' => 'ok', 'model' => 'gadget', 'id' => gadget.id, 'action' => 'fix')
    end

    it 'still reports the record of a Result that has errors as an error' do
      tool = build_tool do |record:, **|
        record.errors.add(:label, :blank)
        success(record:, data: { ignored: true })
      end

      result = tool.call(id: gadget.id, server_context: ctx)

      expect(result.error?).to be(true)
      expect(result.content.first[:text]).to eq("Label can't be blank")
    end

    it 'reports a failed Result with its message as the content and its data as structured content' do
      tool = build_tool { |**| failure('2 unknown slugs', data: { unknown: %w[x y] }) }

      result = tool.call(id: gadget.id, server_context: ctx)

      expect(result.error?).to be(true)
      expect(result.content.pluck(:text)).to eq(['2 unknown slugs'])
      expect(result.structured_content).to eq(error: '2 unknown slugs', data: { 'unknown' => %w[x y] })
    end

    it 'reports a failed Result without data as a message alone, as before' do
      result = build_tool { |**| failure }.call(id: gadget.id, server_context: ctx)

      expect(result.content.pluck(:text)).to eq(['fix failed'])
      expect(result.structured_content).to be_nil
    end

    it 'mirrors the answer as structured content through the server' do
      allow(Administrate::MCP::Actions).to receive(:all_tools).and_return([build_tool { |**| success(data: { n: 1 }) }])
      server = Administrate::MCP::ServerBuilder.build(server_context: ctx.dup)

      response = server.handle(
        { jsonrpc: '2.0', id: 1, method: 'tools/call', params: { name: 'gadget_fix', arguments: { id: gadget.id } } }
      )

      structured = response.dig(:result, :structuredContent)
      expect(structured).to eq(status: 'ok', model: 'gadget', id: gadget.id, action: 'fix', data: { 'n' => 1 })
      expect(JSON.parse(response.dig(:result, :content, 0, :text))).to eq(JSON.parse(structured.to_json))
    end

    it 'encodes the checked copy, not the host object, so its own as_json never runs' do
      sneaky = Class.new(Hash) { def as_json(*) = { 'leaked' => 'secret' } }
      data = sneaky.new.merge!('a' => sneaky.new.merge!('b' => 1))

      result = build_tool { |**| returning(data) }.call(id: gadget.id, server_context: ctx)

      expect(answer(result)['data']).to eq('a' => { 'b' => 1 })
    end
  end

  context 'with a collection action' do
    it 'returns the id of the Result record next to its data' do
      tool = build_tool(model: Widget, on: :collection) do |admin:, **|
        widget = Widget.create!(name: 'Fresh', admin:)
        success(record: widget, data: { warnings: [] })
      end

      result = tool.call(server_context: ctx)

      widget = Widget.find_by!(name: 'Fresh')
      expect(answer(result)).to eq(
        'status' => 'ok', 'model' => 'widget', 'id' => widget.id, 'action' => 'fix', 'data' => { 'warnings' => [] }
      )
    end

    it 'returns data without an id when the Result has no record' do
      tool = build_tool(model: Widget, on: :collection) do |**|
        success(data: { url: 'https://example.com/dump.json', size: 3, ok: true, at: nil })
      end

      expect(answer(tool.call(server_context: ctx))).to eq(
        'status' => 'ok', 'model' => 'widget', 'action' => 'fix',
        'data' => { 'url' => 'https://example.com/dump.json', 'size' => 3, 'ok' => true, 'at' => nil }
      )
    end

    it 'refuses the unsaved record of a Result as before' do
      tool = build_tool(model: Widget, on: :collection) do |**|
        success(record: Widget.new(name: 'Never saved'), data: { a: 1 })
      end

      expect(tool.call(server_context: ctx).content.first[:text]).to eq('fix failed')
    end
  end

  describe 'data that cannot be returned' do
    {
      'a value that is not JSON' => [{ at: Time.utc(2026, 1, 1) }, 'data.at (Time) is not a JSON value'],
      'a nested value that is not JSON' => [{ report: { rows: [1, Object.new] } }, 'data.report.rows[1] (Object)'],
      'an instance of an anonymous class' => [{ row: Struct.new(:a).new(1) }, 'data.row (#<Class:'],
      'a key that is not a String or Symbol' => [{ 1 => 'one' }, 'data has a key (Integer) that is not a String'],
      'the same key as a String and a Symbol' => [{ a: 1, 'a' => 2 }, 'data has the key a twice'],
      'a float that is not finite' => [{ ratio: Float::NAN }, 'data.ratio is not a finite number'],
      'data that is not a Hash' => [%w[a b], 'data (Array) is not a Hash'],
      'a cycle' => [{}.tap { |hash| hash[:self] = hash }, 'is nested deeper than 32 levels'],
      'data nested too deep' => [(1..33).reduce('leaf') { |inner, _| { n: inner } }, 'data.n.n.n']
    }.each do |label, (data, message)|
      it "reports #{label} as an error naming where it is, after the action ran" do
        tool = build_tool do |record:, **|
          record.update!(label: 'Renamed')
          returning(data)
        end

        result = tool.call(id: gadget.id, server_context: ctx)

        expect(result.error?).to be(true)
        expect(result.content.first[:text]).to include('gadget_fix ran, but its data cannot be returned')
        expect(result.content.first[:text]).to include(message)
        expect(gadget.reload.label).to eq('Renamed')
      end
    end

    it 'checks the data of a failure too' do
      tool = build_tool { |**| failure('Nope', data: { at: Time.utc(2026, 1, 1) }) }

      text = tool.call(id: gadget.id, server_context: ctx).content.first[:text]

      expect(text).to include('data.at (Time) is not a JSON value')
    end
  end

  describe 'the size limit' do
    let(:tool) { build_tool { |**| success(data: { rows: Array.new(10) { 'x' * 10 } }) } }

    it 'defaults to 32 KB' do
      expect(Administrate::MCP.config.action_data_max_bytes).to eq(32_768)
    end

    it 'refuses data whose JSON is larger than config.action_data_max_bytes' do
      Administrate::MCP.config.action_data_max_bytes = 139

      text = tool.call(id: gadget.id, server_context: ctx).content.first[:text]

      expect(text).to include('gadget_fix ran, but its data cannot be returned')
      expect(text).to include('is 140 bytes of JSON, over the 139-byte limit (config.action_data_max_bytes)')
    end

    it 'accepts data at the limit' do
      Administrate::MCP.config.action_data_max_bytes = 140

      expect(answer(tool.call(id: gadget.id, server_context: ctx))['data']['rows'].size).to eq(10)
    end

    it 'applies no limit when set to nil' do
      Administrate::MCP.config.action_data_max_bytes = nil

      expect(tool.call(id: gadget.id, server_context: ctx).error?).to be(false)
    end
  end
end
