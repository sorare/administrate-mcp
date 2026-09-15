# frozen_string_literal: true

RSpec.describe Administrate::MCP::BaseTool do
  let(:admin) { create(:admin, :full_access) }
  let(:server_context) { { admin: } }

  let(:open_tool) do
    Class.new(described_class) do
      tool_name 'open_test_tool'
      description 'A test tool with no role restriction'
      input_schema(properties: { msg: { type: 'string' } }, required: ['msg'])

      def self.execute(admin:, msg:) # rubocop:disable Lint/UnusedMethodArgument
        text_response("Hello #{msg}")
      end
    end
  end

  let(:restricted_tool) do
    Class.new(described_class) do
      tool_name 'restricted_test_tool'
      description 'A test tool requiring the widget_manager role'
      input_schema(properties: { placeholder: { type: 'string' } }, required: ['placeholder'])

      requires_roles :widget_manager

      def self.execute(admin:, placeholder: nil) # rubocop:disable Lint/UnusedMethodArgument
        text_response('Authorized')
      end
    end
  end

  describe '.call' do
    it 'delegates to execute and returns a response' do
      result = open_tool.call(msg: 'world', server_context:)

      expect(result).to be_a(MCP::Tool::Response)
      expect(result.content.first[:text]).to eq('Hello world')
    end

    it 'wraps the call in the configured instrumentation hook' do
      seen = []
      Administrate::MCP.config.instrument = lambda do |tool_name:, admin:, &block|
        seen << [tool_name, admin]
        block.call
      end

      open_tool.call(msg: 'world', server_context:)

      expect(seen).to eq([['open_test_tool', admin]])
    end

    it 'reports the call to the configured audit hook' do
      seen = []
      Administrate::MCP.config.on_tool_call = ->(**args) { seen << args }

      open_tool.call(msg: 'world', server_context: { admin:, scopes: ['write'] })

      expect(seen).to eq(
        [{ tool_name: 'open_test_tool', admin:, arguments: { msg: 'world' }, scopes: ['write'] }]
      )
    end

    context 'with role gating' do
      let(:unauthorized_admin) { create(:admin, role: 'viewer') }
      let(:authorized_admin) { create(:admin, role: 'widget_manager') }

      it 'allows access when the admin has the required role' do
        result = restricted_tool.call(placeholder: 'test', server_context: { admin: authorized_admin })

        expect(result.content.first[:text]).to eq('Authorized')
      end

      it 'denies access when the admin lacks the required role' do
        ctx = { admin: unauthorized_admin, authorization_errors: [] }
        result = restricted_tool.call(placeholder: 'test', server_context: ctx)

        expect(result.content.first[:text]).to include('Insufficient permissions')
        expect(ctx[:authorization_errors].first).to include('Insufficient permissions')
      end

      it 'records the refusal when the caller did not seed the array' do
        ctx = { admin: unauthorized_admin }
        restricted_tool.call(placeholder: 'test', server_context: ctx)

        expect(ctx[:authorization_errors].first).to include('Insufficient permissions')
      end
    end

    context 'with scope gating' do
      let(:write_tool) do
        Class.new(described_class) do
          tool_name 'write_test_tool'
          description 'A test tool requiring the write scope'
          input_schema(properties: {})
          requires_scope :write

          def self.execute(admin:, **) # rubocop:disable Lint/UnusedMethodArgument
            text_response('Written')
          end
        end
      end

      it 'refuses a caller without the scope' do
        result = write_tool.call(server_context: { admin:, scopes: [] })

        expect(result.content.first[:text]).to include('Missing required scope(s): write')
      end

      it 'allows a caller carrying the scope' do
        result = write_tool.call(server_context: { admin:, scopes: ['write'] })

        expect(result.content.first[:text]).to eq('Written')
      end
    end
  end

  describe '.text_response' do
    it 'returns a text MCP response' do
      result = open_tool.call(msg: 'test', server_context:)

      expect(result.content).to eq([{ type: 'text', text: 'Hello test' }])
    end
  end

  describe '.json_response' do
    let(:json_tool) do
      Class.new(described_class) do
        tool_name 'json_test_tool'
        description 'Returns JSON'
        input_schema(properties: { placeholder: { type: 'string' } }, required: ['placeholder'])

        def self.execute(admin:, placeholder: nil) # rubocop:disable Lint/UnusedMethodArgument
          json_response({ key: 'value' })
        end
      end
    end

    it 'returns JSON-serialized data' do
      result = json_tool.call(placeholder: 'test', server_context:)

      expect(JSON.parse(result.content.first[:text])).to eq('key' => 'value')
    end
  end
end
