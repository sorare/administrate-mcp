# frozen_string_literal: true

class CreateAdministrateModelContextProtocolAuthorizationTables < ActiveRecord::Migration[8.1]
  def change
    create_table :administrate_mcp_oauth_applications, id: :uuid, if_not_exists: true do |t|
      t.string :client_id, null: false
      t.text :client_secret_digest
      t.text :redirect_uris, array: true, default: [], null: false
      t.string :grant_types, array: true, default: ['authorization_code'], null: false
      t.string :name, null: false

      t.timestamps
    end

    add_index :administrate_mcp_oauth_applications, :client_id, unique: true, if_not_exists: true

    create_table :administrate_mcp_oauth_access_grants, id: :uuid, if_not_exists: true do |t|
      t.uuid :admin_id, null: false
      t.uuid :application_id, null: false
      t.string :token_digest, null: false
      t.integer :expires_in, null: false
      t.text :redirect_uri, null: false
      t.string :scopes, default: ''
      t.string :code_challenge, null: false
      t.string :code_challenge_method, null: false, default: 'S256'
      t.datetime :revoked_at

      t.datetime :created_at, null: false
    end

    add_index :administrate_mcp_oauth_access_grants, :admin_id, if_not_exists: true
    add_index :administrate_mcp_oauth_access_grants, :application_id, if_not_exists: true
    add_index :administrate_mcp_oauth_access_grants, :token_digest, unique: true, if_not_exists: true

    create_table :administrate_mcp_oauth_access_tokens, id: :uuid, if_not_exists: true do |t|
      t.uuid :admin_id, null: false
      t.uuid :application_id, null: false
      t.string :token_digest, null: false
      t.string :refresh_token_digest, null: false
      t.integer :expires_in, null: false
      t.string :scopes, default: ''
      t.datetime :revoked_at

      t.datetime :created_at, null: false
    end

    add_index :administrate_mcp_oauth_access_tokens, :admin_id, if_not_exists: true
    add_index :administrate_mcp_oauth_access_tokens, :application_id, if_not_exists: true
    add_index :administrate_mcp_oauth_access_tokens, :token_digest, unique: true, if_not_exists: true
    add_index :administrate_mcp_oauth_access_tokens, :refresh_token_digest, unique: true, if_not_exists: true
  end
end
