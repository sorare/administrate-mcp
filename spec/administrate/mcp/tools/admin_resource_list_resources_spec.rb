# frozen_string_literal: true

RSpec.describe Administrate::MCP::Tools::AdminResourceListResources do
  let(:admin) { create(:admin, :full_access) }
  let(:server_context) { { admin: } }

  def call(**args)
    JSON.parse(described_class.call(server_context:, **args).content.first[:text])
  end

  describe '.call' do
    context 'without a resource' do
      it 'returns the catalog with the dashboard descriptions' do
        catalog = call

        expect(catalog.pluck('name')).to include('widget', 'gadget', 'admin')
        expect(catalog.find { |r| r['name'] == 'widget' }['description']).to eq(WidgetDashboard::MCP_DESCRIPTION)
      end

      it 'omits a resource the authorization adapter refuses' do
        Administrate::MCP.config.authorization = Class.new(Administrate::MCP::Authorization::Base) do
          def authorized?(_admin, model_class, _action) = model_class != Widget
        end.new

        expect(call.pluck('name')).not_to include('widget')
      end
    end

    context 'with a resource' do
      it 'returns its fields, filters and expandable associations' do
        detail = call(resource: 'widget')

        expect(detail['fields']).to include('id', 'name', 'status')
        expect(detail['expandable']).to eq(['gadgets'])
        expect(detail['filters']).to include(
          { 'name' => 'published', 'type' => 'boolean' },
          { 'name' => 'named', 'type' => 'value' },
          { 'name' => 'admin_id', 'type' => 'value' }
        )
      end

      context 'with MCP_SKIPPED_ATTRIBUTES' do
        before { stub_const('WidgetDashboard::MCP_SKIPPED_ATTRIBUTES', %i[slug]) }

        it 'does not advertise the skipped attribute' do
          fields = call(resource: 'widget')['fields']

          expect(fields).to include('id', 'name')
          expect(fields).not_to include('slug')
        end
      end

      it 'lists the on-demand attributes with their description, apart from the fields' do
        detail = call(resource: 'widget')

        expect(detail['on_demand_fields']).to eq(
          'remote_status' => WidgetDashboard::MCP_ON_DEMAND_ATTRIBUTES[:remote_status]
        )
        expect(detail['fields']).not_to include('remote_status')
      end

      it 'omits on_demand_fields for a dashboard without on-demand attributes' do
        expect(call(resource: 'gadget')).not_to have_key('on_demand_fields')
      end

      context 'when an association is on demand' do
        before { stub_const('WidgetDashboard::MCP_ON_DEMAND_ATTRIBUTES', { gadgets: 'Loaded on request.' }) }

        it 'lists it as on demand and not as expandable' do
          detail = call(resource: 'widget')

          expect(detail['on_demand_fields']).to eq('gadgets' => 'Loaded on request.')
          expect(detail).not_to have_key('expandable')
        end
      end

      context 'when the on-demand attribute is also skipped' do
        before { stub_const('WidgetDashboard::MCP_SKIPPED_ATTRIBUTES', %i[remote_status]) }

        it 'omits on_demand_fields' do
          expect(call(resource: 'widget')).not_to have_key('on_demand_fields')
        end
      end

      it_behaves_like 'a tool reporting resource errors', verb: 'list'
    end
  end
end
