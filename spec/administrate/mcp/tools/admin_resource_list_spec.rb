# frozen_string_literal: true

RSpec.describe Administrate::MCP::Tools::AdminResourceList do
  let(:admin) { create(:admin, :full_access) }
  let(:server_context) { { admin: } }

  def call(**args)
    JSON.parse(described_class.call(server_context:, **args).content.first[:text])
  end

  describe '.call' do
    before { create_list(:widget, 3) }

    it 'returns columns, rows and pagination meta' do
      data = call(resource: 'widget')

      expect(data['columns']).to eq(%w[url id name status])
      expect(data['rows'].size).to eq(3)
      expect(data['meta']).to include('page' => 1, 'per_page' => 10, 'total_count' => 3, 'total_pages' => 1)
    end

    it 'caps per_page at the maximum' do
      expect(call(resource: 'widget', per_page: 500)['meta']['per_page']).to eq(described_class::MAX_PER_PAGE)
    end

    it 'honours the MCP_BASE_SCOPE, which sees rows the model default scope hides' do
      create(:widget, status: :archived)

      expect(call(resource: 'widget')['meta']['total_count']).to eq(4)
    end

    it 'restricts the columns to the requested fields' do
      expect(call(resource: 'widget', fields: %w[id name])['columns']).to eq(%w[url id name])
    end

    it 'rejects an unknown field' do
      result = described_class.call(server_context:, resource: 'widget', fields: %w[nope])

      expect(result.content.first[:text]).to include('Unknown fields: nope')
    end

    it 'rejects an unknown resource as an authorization error' do
      ctx = { admin: }
      result = described_class.call(server_context: ctx, resource: 'nonexistent')

      expect(result.content.first[:text]).to include('Unknown resource: nonexistent')
      expect(ctx[:authorization_errors]).not_to be_empty
    end

    describe 'search' do
      it 'matches an exact slug' do
        widget = Widget.first

        expect(call(resource: 'widget', query: widget.slug)['meta']['total_count']).to eq(1)
      end

      it 'matches a wildcard' do
        expect(call(resource: 'widget', query: '*widget*')['meta']['total_count']).to eq(3)
      end
    end

    describe 'filters' do
      it 'applies a boolean dashboard filter' do
        Widget.first.update!(status: :published)

        expect(call(resource: 'widget', filters: { 'published' => true })['meta']['total_count']).to eq(1)
      end

      it 'applies a value dashboard filter' do
        widget = Widget.first

        expect(call(resource: 'widget', filters: { 'named' => widget.name })['meta']['total_count']).to eq(1)
      end

      it 'applies a foreign key filter that no dashboard declares' do
        widget = Widget.first

        expect(call(resource: 'widget', filters: { 'admin_id' => widget.admin_id })['meta']['total_count']).to eq(1)
      end

      it 'rejects an unknown filter' do
        result = described_class.call(server_context:, resource: 'widget', filters: { 'nope' => 1 })

        expect(result.content.first[:text]).to include('Unknown filters: nope')
      end
    end

    describe 'sorting' do
      it 'sorts by a dashboard attribute' do
        names = call(resource: 'widget', sort: 'name', sort_direction: 'asc')['rows'].pluck(2)

        expect(names).to eq(names.sort)
      end

      it 'rejects a sort on an attribute MCP_SKIPPED_ATTRIBUTES hides' do
        stub_const('WidgetDashboard::MCP_SKIPPED_ATTRIBUTES', %i[slug])

        result = described_class.call(server_context:, resource: 'widget', sort: 'slug')

        expect(result.content.first[:text]).to include('Unknown sort fields: slug')
      end

      it 'rejects an unknown sort field' do
        result = described_class.call(server_context:, resource: 'widget', sort: 'nope')

        expect(result.content.first[:text]).to include('Unknown sort fields: nope')
      end
    end

    describe 'expansion' do
      it 'adds the expanded association to the columns' do
        widget = Widget.first
        create(:gadget, widget:)

        data = call(resource: 'widget', fields: %w[id], expand: %w[gadgets])

        expect(data['columns']).to eq(%w[url id gadgets])
      end

      it 'rejects more expansions than the cap allows' do
        result = described_class.call(server_context:, resource: 'widget', expand: %w[gadgets gadgets gadgets])

        expect(result.content.first[:text]).to include('Too many expansions')
      end

      it 'rejects an association that is not expandable' do
        result = described_class.call(server_context:, resource: 'widget', expand: %w[name])

        expect(result.content.first[:text]).to include('Unknown expandable associations: name')
      end
    end
  end
end
