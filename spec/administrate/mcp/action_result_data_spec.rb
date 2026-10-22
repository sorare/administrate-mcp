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

  describe 'Administrate::MCP::Result' do
    it 'is a success unless built as a failure' do
      expect(Administrate::MCP::Result.success).to have_attributes(success?: true, record: nil, data: nil)
      expect(Administrate::MCP::Result.new(record: gadget, data: { a: 1 }))
        .to have_attributes(success?: true, record: gadget, mcp_data: { a: 1 })
      expect(Administrate::MCP::Result.failure('Nope', data: { b: 2 }))
        .to have_attributes(success?: false, error: 'Nope', mcp_data: { b: 2 })
    end
  end

  context 'with a member action' do
    it 'adds the data of a Result to the response under data' do
      tool = build_tool do |record:, **|
        previous = record.label
        record.update!(label: 'Renamed')
        Administrate::MCP::Result.success(record:, data: { previous_label: previous })
      end

      result = tool.call(id: gadget.id, server_context: ctx)

      expect(answer(result)).to eq(
        'status' => 'ok', 'model' => 'gadget', 'id' => gadget.id, 'action' => 'fix',
        'data' => { 'previous_label' => gadget.label }
      )
      expect(gadget.reload.label).to eq('Renamed')
    end

    it 'adds the mcp_data of any result object that answers it' do
      report = Struct.new(:mcp_data).new({ created: 2, missing: %w[a b] })

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
        Administrate::MCP::Result.success(record:, data: { ignored: true })
      end

      result = tool.call(id: gadget.id, server_context: ctx)

      expect(result.error?).to be(true)
      expect(result.content.first[:text]).to eq("Label can't be blank")
    end

    it 'reports a failed Result with its message first and its data as a second content block' do
      tool = build_tool { |**| Administrate::MCP::Result.failure('2 unknown slugs', data: { unknown: %w[x y] }) }

      result = tool.call(id: gadget.id, server_context: ctx)

      expect(result.error?).to be(true)
      expect(result.content.first[:text]).to eq('2 unknown slugs')
      expect(JSON.parse(result.content.second[:text]))
        .to eq('error' => '2 unknown slugs', 'data' => { 'unknown' => %w[x y] })
    end

    it 'reports a failed Result without data as a single message, as before' do
      result = build_tool { |**| Administrate::MCP::Result.failure }.call(id: gadget.id, server_context: ctx)

      expect(result.content.pluck(:text)).to eq(['fix failed'])
    end
  end

  context 'with a collection action' do
    it 'returns the id of the Result record next to its data' do
      tool = build_tool(model: Widget, on: :collection) do |admin:, **|
        widget = Widget.create!(name: 'Fresh', admin:)
        Administrate::MCP::Result.success(record: widget, data: { warnings: [] })
      end

      result = tool.call(server_context: ctx)

      widget = Widget.find_by!(name: 'Fresh')
      expect(answer(result)).to eq(
        'status' => 'ok', 'model' => 'widget', 'id' => widget.id, 'action' => 'fix', 'data' => { 'warnings' => [] }
      )
    end

    it 'returns data without an id when the Result has no record' do
      tool = build_tool(model: Widget, on: :collection) do |**|
        Administrate::MCP::Result.success(data: { url: 'https://example.com/dump.json', size: 3, ok: true, at: nil })
      end

      expect(answer(tool.call(server_context: ctx))).to eq(
        'status' => 'ok', 'model' => 'widget', 'action' => 'fix',
        'data' => { 'url' => 'https://example.com/dump.json', 'size' => 3, 'ok' => true, 'at' => nil }
      )
    end

    it 'refuses the unsaved record of a Result as before' do
      tool = build_tool(model: Widget, on: :collection) do |**|
        Administrate::MCP::Result.success(record: Widget.new(name: 'Never saved'), data: { a: 1 })
      end

      expect(tool.call(server_context: ctx).content.first[:text]).to eq('fix failed')
    end
  end

  describe 'data that cannot be returned' do
    {
      'a value that is not JSON' => [{ at: Time.utc(2026, 1, 1) }, 'data.at is a Time'],
      'a nested value that is not JSON' => [{ report: { rows: [1, Object.new] } }, 'data.report.rows[1] is an Object'],
      'a key that is not a String or Symbol' => [{ 1 => 'one' }, 'data has an Integer key'],
      'a float that is not finite' => [{ ratio: Float::NAN }, 'data.ratio is not a finite number'],
      'data that is not a Hash' => [%w[a b], 'data is an Array, not a Hash']
    }.each do |label, (data, message)|
      it "reports #{label} as an error naming where it is, after the action ran" do
        tool = build_tool do |record:, **|
          record.update!(label: 'Renamed')
          Struct.new(:mcp_data).new(data)
        end

        result = tool.call(id: gadget.id, server_context: ctx)

        expect(result.error?).to be(true)
        expect(result.content.first[:text]).to include('gadget_fix ran, but its data cannot be returned')
        expect(result.content.first[:text]).to include(message)
        expect(gadget.reload.label).to eq('Renamed')
      end
    end

    it 'checks the data of a failure too' do
      tool = build_tool { |**| Administrate::MCP::Result.failure('Nope', data: { at: Time.utc(2026, 1, 1) }) }

      expect(tool.call(id: gadget.id, server_context: ctx).content.first[:text]).to include('data.at is a Time')
    end
  end

  describe 'the size limit' do
    let(:tool) { build_tool { |**| Administrate::MCP::Result.success(data: { rows: Array.new(10) { 'x' * 10 } }) } }

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
