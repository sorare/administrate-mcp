# frozen_string_literal: true

class CreateAdministrateModelContextProtocolApiKeys < ActiveRecord::Migration[8.1]
  def change
    admin_foreign_key = Administrate::MCP.config.admin_foreign_key

    create_table :administrate_mcp_api_keys, id: :uuid, if_not_exists: true do |t|
      t.uuid admin_foreign_key, null: false
      t.string :token_digest, null: false
      t.string :token_prefix, null: false
      t.string :name, null: false
      t.boolean :write_access, null: false, default: false
      t.datetime :last_used_at
      t.datetime :revoked_at

      t.timestamps
    end

    add_index :administrate_mcp_api_keys, admin_foreign_key, if_not_exists: true
    add_index :administrate_mcp_api_keys, :token_digest, unique: true, if_not_exists: true
  end
end
