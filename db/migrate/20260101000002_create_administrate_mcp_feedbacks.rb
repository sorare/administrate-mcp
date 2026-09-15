# frozen_string_literal: true

class CreateAdministrateMcpFeedbacks < ActiveRecord::Migration[8.1]
  def change
    create_table :administrate_mcp_feedbacks, id: :uuid, if_not_exists: true do |t|
      t.uuid :admin_id
      t.uuid :api_key_id
      t.integer :category, null: false
      t.string :resource_name
      t.text :suggestion, null: false
      t.integer :status, null: false, default: 0

      t.timestamps
    end

    add_index :administrate_mcp_feedbacks, :admin_id, if_not_exists: true
    add_index :administrate_mcp_feedbacks, :api_key_id, if_not_exists: true
  end
end
