# frozen_string_literal: true

RSpec.describe 'authorization adapters' do
  let(:admin) { create(:admin, role: 'widget_manager') }
  let(:widget) { create(:widget) }

  describe Administrate::MCP::Authorization::Permissive do
    subject(:adapter) { described_class.new }

    it 'allows every action' do
      expect(adapter.authorized?(admin, Widget, :index?)).to be(true)
      expect { adapter.authorize!(admin, widget, :destroy?) }.not_to raise_error
    end

    it 'still enforces roles' do
      expect { adapter.authorize_roles!(admin, [:widget_manager]) }.not_to raise_error
      expect { adapter.authorize_roles!(admin, [:nope]) }.to raise_error(
        Administrate::MCP::UnauthorizedError,
        'Insufficient permissions. Required roles: nope'
      )
    end

    it 'skips the role check for an admin that does not answer can_access?' do
      expect { adapter.authorize_roles!(Object.new, [:nope]) }.not_to raise_error
    end
  end

  describe Administrate::MCP::Authorization::Pundit do
    subject(:adapter) { described_class.new }

    before do
      stub_const(
        'WidgetPolicy',
        Class.new do
          def initialize(admin, record)
            @admin = admin
            @record = record
          end

          def index? = @admin.can_access?(:widget_manager)

          def show? = index?

          def destroy? = false
        end
      )
    end

    it 'allows an action the policy grants' do
      expect(adapter.authorized?(admin, Widget, :index?)).to be(true)
    end

    it 'refuses an action the policy denies' do
      expect(adapter.authorized?(admin, widget, :destroy?)).to be(false)
      expect { adapter.authorize!(admin, widget, :destroy?) }.to raise_error(
        Administrate::MCP::UnauthorizedError,
        'Not authorized to destroy? Widget'
      )
    end

    it 'refuses an action for an admin the policy does not recognise' do
      expect(adapter.authorized?(create(:admin, role: 'viewer'), Widget, :index?)).to be(false)
    end

    it 'reports a missing policy as unauthorized rather than raising' do
      expect(adapter.authorized?(admin, Gadget, :index?)).to be(false)
    end
  end
end
