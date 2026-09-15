# frozen_string_literal: true

ActiveRecord::Schema[8.1].define(version: 0) do
  enable_extension 'pgcrypto'

  create_table :admins, id: :uuid, force: :cascade do |t|
    t.string :email, null: false
    t.string :role, null: false, default: 'viewer'
    t.timestamps
  end

  create_table :widgets, id: :uuid, force: :cascade do |t|
    t.uuid :admin_id
    t.string :name, null: false
    t.string :slug
    t.integer :status, null: false, default: 0
    t.integer :price
    t.boolean :featured, null: false, default: false
    t.string :secret
    t.timestamps
  end

  create_table :gadgets, id: :uuid, force: :cascade do |t|
    t.uuid :widget_id, null: false
    t.string :label, null: false
    t.timestamps
  end
end
