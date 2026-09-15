# frozen_string_literal: true

RSpec.describe Administrate::MCP::DashboardRegistry do
  after { described_class.reset! }

  describe '.find' do
    it 'returns an entry for a known resource' do
      entry = described_class.find('widget')

      expect(entry).to be_present
      expect(entry.dashboard_class).to eq(WidgetDashboard)
      expect(entry.model_class).to eq(Widget)
    end

    it 'returns nil for an unknown resource' do
      expect(described_class.find('nonexistent_xyz')).to be_nil
    end

    it 'handles singular/plural and case variations' do
      expect(described_class.find('Widgets')&.model_class).to eq(Widget)
    end

    it 'reads MCP_DESCRIPTION off the dashboard' do
      expect(described_class.find('widget').description).to eq(WidgetDashboard::MCP_DESCRIPTION)
    end

    it 'uses MCP_BASE_SCOPE as the entry scope' do
      entry = described_class.find('widget')

      expect(entry.scope.to_sql).to eq(Widget.unscope(where: :status).to_sql)
    end

    it 'defaults the entry scope to the model default scope' do
      entry = described_class.find('gadget')

      expect(entry.base_scope).to be_nil
      expect(entry.scope.to_sql).to eq(Gadget.all.to_sql)
    end
  end

  describe '.resource_names' do
    it 'returns a sorted array of resource names' do
      names = described_class.resource_names

      expect(names).to include('widget', 'gadget', 'admin')
      expect(names).to eq(names.sort)
    end

    it 'does not include descriptions as resource names' do
      expect(described_class.resource_names).to all(match(%r{\A[a-z0-9_/]+\z}))
    end
  end

  describe '.registry' do
    it 'builds entries with dashboard and model classes' do
      expect(described_class.registry.values).to all(be_a(described_class::Entry))
    end

    it 'includes only dashboards with a resolvable model class' do
      described_class.registry.each_value do |entry|
        expect(entry.dashboard_class).to be < Administrate::BaseDashboard
        expect(entry.model_class).to be_present
      end
    end
  end

  describe '.dashboard_class_name' do
    it 'derives the fully qualified class name from the file path' do
      file = Rails.root.join('app/dashboards/widget_dashboard.rb').to_s

      expect(described_class.dashboard_class_name(file)).to eq('WidgetDashboard')
    end
  end

  describe 'dashboard constants' do
    it 'leaves out a dashboard that sets MCP_EXPOSED to false' do
      stub_const('GadgetDashboard::MCP_EXPOSED', false)
      described_class.reset!

      expect(described_class.find('gadget')).to be_nil
    end

    it 'reads MCP_SKIPPED_ATTRIBUTES as symbols' do
      stub_const('WidgetDashboard::MCP_SKIPPED_ATTRIBUTES', %w[slug])

      expect(described_class.skipped_attributes(WidgetDashboard)).to eq(%i[slug])
    end

    it 'uses the model the dashboard declares' do
      allow(WidgetDashboard).to receive(:model).and_return(Gadget)
      described_class.reset!

      expect(described_class.find('gadget').dashboard_class).to eq(WidgetDashboard)
    end
  end
end
