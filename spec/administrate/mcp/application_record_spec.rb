# frozen_string_literal: true

RSpec.describe Administrate::MCP::ApplicationRecord do
  describe '.belongs_to_admin' do
    let(:table) { 'administrate_mcp_admin_foreign_key_spec_records' }

    before do
      ActiveRecord::Base.connection.create_table(table, id: :uuid) do |t|
        t.uuid :administrator_id, null: false
      end
    end

    after do
      ActiveRecord::Base.connection.drop_table(table, if_exists: true)
    end

    it 'reads and writes the admin through the configured foreign key column' do
      Administrate::MCP.config.admin_foreign_key = :administrator_id
      table_name = table

      stub_const('AdminForeignKeySpecRecord', Class.new(described_class) do
        self.table_name = table_name

        belongs_to_admin
      end)
      model = AdminForeignKeySpecRecord

      admin = create(:admin)
      record = model.create!(admin:)

      expect(record.reload.administrator_id).to eq(admin.id)
      expect(model.find(record.id).admin).to eq(admin)
    end
  end
end
