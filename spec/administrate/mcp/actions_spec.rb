# frozen_string_literal: true

RSpec.describe Administrate::MCP::Actions do
  let(:admin) { create(:admin, :full_access) }
  let(:gadget) { create(:gadget) }

  after { described_class.reset! }

  describe '.build_spec' do
    it 'defaults the predicate to the action name and the scope to write' do
      spec = described_class.build_spec(:approve, description: 'Approve it') { nil }

      expect(spec).to include(name: :approve, predicate: :approve?, scope: :write, destructive: true)
    end

    it 'accepts the pundit: alias for the predicate' do
      spec = described_class.build_spec(:approve, description: 'Approve it', pundit: :moderate?) { nil }

      expect(spec[:predicate]).to eq(:moderate?)
    end

    it 'expands a String param into a string schema and marks it required' do
      spec = described_class.build_spec(:comment, description: 'Comment', params: { body: 'The body' }) { nil }

      expect(spec[:params]).to eq(body: { type: 'string', description: 'The body' })
      expect(spec[:required]).to eq([:body])
    end

    it 'leaves an explicitly optional param out of required' do
      spec =
        described_class.build_spec(
          :comment,
          description: 'Comment',
          params: { body: { type: 'string', required: false } }
        ) { nil }

      expect(spec[:required]).to eq([])
      expect(spec[:params][:body]).not_to have_key(:required)
    end

    it 'demands an invocation block' do
      expect { described_class.build_spec(:comment, description: 'Comment') }.to raise_error(ArgumentError)
    end

    %w[admin id].each do |reserved|
      it "refuses a param named #{reserved}" do
        expect { described_class.build_spec(:comment, description: 'Comment', params: { reserved => 'Taken' }) { nil } }
          .to raise_error(ArgumentError, /reserved param name\(s\): #{reserved}/)
      end
    end

    it 'accepts params named like the block keywords they are nested under' do
      spec = described_class.build_spec(:comment, description: 'Comment', params: { record: 'R', params: 'P' }) { nil }

      expect(spec[:params].keys).to eq(%i[record params])
    end
  end

  describe '.definitions' do
    it 'picks up the dashboard declaration' do
      definition = described_class.definitions.find { |d| d.name == :relabel }

      expect(definition.model_class).to eq(Gadget)
      expect(definition.predicate).to eq(:relabel?)
    end
  end

  describe '.tools_for' do
    it 'hides the tool from a caller without the write scope' do
      names = described_class.tools_for({ admin:, scopes: [] }).map(&:name_value)

      expect(names).to be_empty
    end

    it 'exposes the tool once the write scope is granted' do
      names = described_class.tools_for({ admin:, scopes: ['write'] }).map(&:name_value)

      expect(names).to eq(['gadget_relabel'])
    end

    context 'with an authorization adapter that refuses the predicate' do
      before do
        Administrate::MCP.config.authorization = Class.new(Administrate::MCP::Authorization::Base) do
          def authorized?(_admin, _record_or_class, _action) = false
        end.new
      end

      it 'hides the tool' do
        expect(described_class.tools_for({ admin:, scopes: ['write'] })).to be_empty
      end
    end
  end

  describe 'the generated tool' do
    subject(:tool) { described_class.tools_for({ admin:, scopes: ['write'] }).first }

    it 'requires an id plus the declared params' do
      expect(tool.input_schema.to_h[:required]).to eq(%w[id label])
    end

    it 'refuses undeclared arguments' do
      expect(tool.input_schema.to_h[:additionalProperties]).to be(false)
    end

    it 'runs the declared block against the loaded record' do
      result = tool.call(id: gadget.id, label: 'Renamed', server_context: { admin:, scopes: ['write'] })

      expect(JSON.parse(result.content.first[:text])).to include('status' => 'ok', 'action' => 'relabel')
      expect(gadget.reload.label).to eq('Renamed')
    end

    it 'reports an unknown record as an authorization error' do
      ctx = { admin:, scopes: ['write'] }
      result = tool.call(id: SecureRandom.uuid, label: 'Renamed', server_context: ctx)

      expect(result.content.first[:text]).to include('not found')
      expect(ctx[:authorization_errors]).not_to be_empty
    end
  end
end
