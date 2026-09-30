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

    describe 'on-demand attributes' do
      it 'leaves them out of a default single show' do
        expect(call(resource: 'widget', id: widget.id)).not_to have_key('remote_status')
      end

      it 'resolves them when a single show names them' do
        data = call(resource: 'widget', id: widget.id, fields: %w[id remote_status])

        expect(data).to include('remote_status' => "remote-#{widget.name}")
      end

      it 'leaves them out of a default batch show' do
        data = call(resource: 'widget', id: [widget.id])

        expect(data['columns']).not_to include('remote_status')
      end

      it 'refuses them in a batch show' do
        result = described_class.call(server_context:, resource: 'widget', id: [widget.id],
                                      fields: %w[id remote_status])

        expect(result.content.first[:text]).to include(
          'Field `remote_status` is resolved on demand, only by admin_resource_show with a single id.'
        )
      end

      it 'reports a skipped one as unknown' do
        stub_const('WidgetDashboard::MCP_SKIPPED_ATTRIBUTES', %i[remote_status])

        result = described_class.call(server_context:, resource: 'widget', id: widget.id, fields: %w[remote_status])

        expect(result.content.first[:text]).to include('Unknown fields: remote_status')
      end
    end

    context 'when SHOW_PAGE_ATTRIBUTES is a Hash of groups' do
      before do
        stub_const('WidgetDashboard::SHOW_PAGE_ATTRIBUTES', { '' => %i[id name], 'Details' => %i[slug remote_status] })
      end

      it 'returns the grouped attributes without the on-demand one' do
        data = call(resource: 'widget', id: widget.id)

        expect(data).to include('id' => widget.id, 'name' => widget.name, 'slug' => widget.slug)
        expect(data).not_to have_key('remote_status')
      end

      it 'resolves an on-demand attribute named in the grouped attributes' do
        data = call(resource: 'widget', id: widget.id, fields: %w[remote_status])

        expect(data).to include('remote_status' => "remote-#{widget.name}")
      end
    end

    it_behaves_like 'a tool reporting resource errors', verb: 'show', arguments: { id: 'any' }

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
