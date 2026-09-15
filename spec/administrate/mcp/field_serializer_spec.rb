# frozen_string_literal: true

RSpec.describe Administrate::MCP::FieldSerializer do
  let(:admin) { create(:admin) }
  let(:widget) { create(:widget, admin:, status: :published, price: 42, featured: true) }
  let(:dashboard) { WidgetDashboard.new }

  describe '.serialize' do
    it 'returns a hash of serialized fields' do
      result = described_class.serialize(widget, dashboard)

      expect(result[:id]).to eq(widget.id)
      expect(result[:slug]).to eq(widget.slug)
      expect(result[:url]).to end_with("/admin/widgets/#{widget.to_param}")
    end

    it 'only includes the requested attributes plus url' do
      result = described_class.serialize(widget, dashboard, attributes: %i[id slug])

      expect(result.keys).to contain_exactly(:url, :id, :slug)
    end

    it 'serializes DateTime to ISO 8601' do
      result = described_class.serialize(widget, dashboard, attributes: %i[created_at])

      expect(result[:created_at]).to eq(widget.created_at.iso8601)
    end

    it 'serializes a Select field to a string' do
      result = described_class.serialize(widget, dashboard, attributes: %i[status])

      expect(result[:status]).to eq('published')
    end

    it 'serializes Number and Boolean fields to their native values' do
      result = described_class.serialize(widget, dashboard, attributes: %i[price featured])

      expect(result[:price]).to eq(42)
      expect(result[:featured]).to be(true)
    end

    it 'serializes a BelongsTo to a hash carrying the id and the dashboard display' do
      result = described_class.serialize(widget, dashboard, attributes: %i[admin])

      expect(result[:admin]).to include(id: admin.id, display: admin.email)
    end

    it 'serializes a nil BelongsTo to nil' do
      result = described_class.serialize(create(:widget, admin: nil), dashboard, attributes: %i[admin])

      expect(result[:admin]).to be_nil
    end

    it 'serializes a HasMany to a count' do
      create(:gadget, widget:)

      result = described_class.serialize(widget, dashboard, attributes: %i[gadgets])

      expect(result[:gadgets]).to eq({ count: 1 })
    end

    it 'expands a HasMany inline when asked' do
      gadget = create(:gadget, widget:)

      result = described_class.serialize(widget, dashboard, attributes: %i[gadgets], expand: Set[:gadgets])

      expect(result[:gadgets][:count]).to eq(1)
      expect(result[:gadgets][:items].first[:label]).to eq(gadget.label)
    end

    it 'does not expand fields outside the expand set' do
      result = described_class.serialize(widget, dashboard, attributes: %i[gadgets], expand: Set[:other])

      expect(result[:gadgets]).to eq({ count: 0 })
    end

    it 'skips the field classes the configuration excludes' do
      result = described_class.serialize(widget, dashboard)

      expect(result).not_to have_key(:secret)
    end

    context 'when an attribute raises' do
      before { allow(widget).to receive(:admin).and_raise(ActiveRecord::StatementInvalid, 'boom') }

      it 'keeps the nil the field type already returns rather than leaking an error string' do
        result = described_class.serialize(widget, dashboard, attributes: %i[admin])

        expect(result[:admin]).to be_nil
      end
    end

    context 'with a host field class registered through the configuration' do
      let(:money_field) { Class.new(Administrate::Field::Base) }

      before do
        stub_const('MoneyField', money_field)
        Administrate::MCP.config.register_field('MoneyField') { |source| { cents: source.value } }
        allow(dashboard).to receive(:attribute_types).and_return(price: MoneyField)
      end

      it 'uses the registered serializer' do
        result = described_class.serialize(widget, dashboard, attributes: %i[price])

        expect(result[:price]).to eq({ cents: 42 })
      end
    end

    context 'with a field class exposing mcp_value' do
      let(:json_field) do
        Class.new(Administrate::Field::Base) do
          def self.mcp_value(record, _attr_name)
            { computed: record.name }
          end
        end
      end

      before do
        stub_const('HostJsonField', json_field)
        allow(dashboard).to receive(:attribute_types).and_return(name: HostJsonField)
      end

      it 'calls mcp_value' do
        result = described_class.serialize(widget, dashboard, attributes: %i[name])

        expect(result[:name]).to eq({ computed: widget.name })
      end
    end

    context 'with a subclass of a registered field class that defines mcp_value' do
      let(:rich_string_field) do
        Class.new(Administrate::Field::String) do
          def self.mcp_value(record, _attr_name)
            { parsed: record.name.upcase }
          end
        end
      end

      before do
        stub_const('RichStringField', rich_string_field)
        allow(dashboard).to receive(:attribute_types).and_return(name: RichStringField)
      end

      it 'prefers mcp_value over the serializer registered for the parent' do
        result = described_class.serialize(widget, dashboard, attributes: %i[name])

        expect(result[:name]).to eq({ parsed: widget.name.upcase })
      end
    end

    context 'with an unregistered field class' do
      let(:unknown_field) { Class.new(Administrate::Field::Base) }

      before do
        stub_const('UnknownField', unknown_field)
        allow(dashboard).to receive(:attribute_types).and_return(name: UnknownField)
      end

      it 'falls back to the raw value instead of an error string' do
        result = described_class.serialize(widget, dashboard, attributes: %i[name])

        expect(result[:name]).to eq(widget.name)
      end
    end
  end

  describe '.admin_url_for' do
    it 'generates an admin URL ending with the resource path' do
      expect(described_class.admin_url_for(widget)).to eq("https://admin.example.com/admin/widgets/#{widget.to_param}")
    end

    it 'returns nil for non-AR records' do
      expect(described_class.admin_url_for(Object.new)).to be_nil
    end

    context 'when admin_origin is a proc that reads the request' do
      around do |example|
        previous = Rails.application.routes.default_url_options
        Rails.application.routes.default_url_options = { host: 'fallback.example.com', protocol: 'https' }
        example.run
        Rails.application.routes.default_url_options = previous
      end

      before do
        Administrate::MCP.config.admin_url_options = {}
        Administrate::MCP.config.admin_origin = ->(request) { "https://#{request.subdomain}.example.com" }
      end

      it 'still builds the url from default_url_options rather than losing it' do
        expect(described_class.admin_url_for(widget)).to eq(
          "https://fallback.example.com/admin/widgets/#{widget.to_param}"
        )
      end
    end
  end

  describe '.resolve_columns' do
    it 'returns only non-skipped attributes' do
      expect(described_class.resolve_columns(dashboard, %i[id slug secret])).to contain_exactly(:id, :slug)
    end

    it 'falls back to show_page_attributes when no attributes are given' do
      columns = described_class.resolve_columns(dashboard, nil)

      expect(columns).to include(:id, :slug)
      expect(columns).not_to include(:secret)
    end
  end

  describe '.serialize_row' do
    it 'returns an array of values in column order' do
      expect(described_class.serialize_row(widget, dashboard, columns: %i[id slug])).to eq([widget.id, widget.slug])
    end

    it 'honours the expand set' do
      row = described_class.serialize_row(widget, dashboard, columns: %i[id gadgets], expand: Set[:gadgets])

      expect(row.last).to include(:count, :items)
    end
  end

  describe '.resolve_field_class' do
    it 'resolves a plain class' do
      expect(described_class.resolve_field_class(Administrate::Field::String)).to eq(Administrate::Field::String)
    end

    it 'resolves a Deferred field' do
      deferred = Administrate::Field::String.with_options(searchable: false)

      expect(described_class.resolve_field_class(deferred)).to eq(Administrate::Field::String)
    end
  end

  describe '.skip_field?' do
    it 'skips the configured classes' do
      expect(described_class.skip_field?(Administrate::Field::Password)).to be(true)
    end

    it 'does not skip String fields' do
      expect(described_class.skip_field?(Administrate::Field::String)).to be(false)
    end
  end

  describe 'MCP_SKIPPED_ATTRIBUTES' do
    let(:widget) { create(:widget) }

    before { stub_const('WidgetDashboard::MCP_SKIPPED_ATTRIBUTES', %i[slug]) }

    it 'omits the attribute from a serialized record' do
      result = described_class.serialize(widget, WidgetDashboard.new, attributes: %i[id slug])

      expect(result).to have_key(:id)
      expect(result).not_to have_key(:slug)
    end

    it 'omits the attribute from the resolved columns' do
      expect(described_class.exposed_attributes(WidgetDashboard.new)).not_to include(:slug)
    end
  end

  describe 'admin URL host fallback' do
    let(:widget) { create(:widget) }

    before { Administrate::MCP.config.admin_url_options = {} }
    after { Administrate::MCP.config.admin_url_options = { host: 'admin.example.com', protocol: 'https' } }

    it 'takes the host from admin_origin when none is configured' do
      result = described_class.serialize(widget, WidgetDashboard.new, attributes: %i[id])

      expect(result[:url]).to start_with('https://admin.example.com/')
    end
  end
end
