# frozen_string_literal: true

RSpec.describe Administrate::MCP::Tools::AdminResourceShow do
  let(:admin) { create(:admin, :full_access) }
  let(:server_context) { { admin: } }
  let!(:widget) { create(:widget) }

  def call(**args)
    JSON.parse(described_class.call(server_context:, **args).content.first[:text])
  end

  describe '.call' do
    it 'returns the show page attributes for one record' do
      data = call(resource: 'widget', id: widget.id)

      expect(data).to include('id' => widget.id, 'name' => widget.name)
      expect(data['url']).to end_with("/admin/widgets/#{widget.to_param}")
    end

    it 'restricts the response to the requested fields' do
      expect(call(resource: 'widget', id: widget.id, fields: %w[id name]).keys).to contain_exactly('url', 'id', 'name')
    end

    it 'reports a missing record' do
      result = described_class.call(server_context:, resource: 'widget', id: SecureRandom.uuid)

      expect(result.content.first[:text]).to include('not found for')
    end

    it 'finds a record the model default scope hides, through MCP_BASE_SCOPE' do
      archived = create(:widget, status: :archived)

      expect(call(resource: 'widget', id: archived.id)['id']).to eq(archived.id)
    end

    it 'expands a HasMany inline' do
      create(:gadget, widget:)

      data = call(resource: 'widget', id: widget.id, fields: %w[id], expand: %w[gadgets])

      expect(data['gadgets']).to include('count' => 1)
      expect(data['gadgets']['items'].size).to eq(1)
    end

    describe 'batch lookup' do
      let!(:other) { create(:widget) }

      it 'returns a columns/rows payload' do
        data = call(resource: 'widget', id: [widget.id, other.id], fields: %w[id name])

        expect(data['columns']).to eq(%w[url id name])
        expect(data['rows'].pluck(1)).to contain_exactly(widget.id, other.id)
      end

      it 'reports the ids it could not find inline' do
        data = call(resource: 'widget', id: [widget.id, SecureRandom.uuid], fields: %w[id])

        expect(data['rows'].last).to include('error' => 'Widget not found')
      end

      it 'refuses more ids than the cap allows' do
        result = described_class.call(server_context:, resource: 'widget', id: Array.new(11) { SecureRandom.uuid })

        expect(result.content.first[:text]).to include('Too many ids')
      end
    end
  end
end
