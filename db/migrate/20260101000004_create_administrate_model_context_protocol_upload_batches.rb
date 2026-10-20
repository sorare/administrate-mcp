# frozen_string_literal: true

class CreateAdministrateModelContextProtocolUploadBatches < ActiveRecord::Migration[8.1]
  def change
    admin_foreign_key = Administrate::MCP.config.admin_foreign_key

    create_table :administrate_mcp_upload_batches, id: :uuid, if_not_exists: true do |t|
      t.uuid admin_foreign_key, null: false
      t.datetime :expires_at, null: false
      t.jsonb :files, null: false, default: []

      t.timestamps
    end

    add_index :administrate_mcp_upload_batches, admin_foreign_key, if_not_exists: true
    add_index :administrate_mcp_upload_batches, :files, using: :gin, opclass: :jsonb_path_ops, if_not_exists: true
  end
end
