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
    t.jsonb :picture_data
    t.timestamps
  end

  create_table :gadgets, id: :uuid, force: :cascade do |t|
    t.uuid :widget_id, null: false
    t.string :label, null: false
    t.timestamps
  end

  create_table :active_storage_blobs, force: :cascade do |t|
    t.string :key, null: false
    t.string :filename, null: false
    t.string :content_type
    t.text :metadata
    t.string :service_name, null: false
    t.bigint :byte_size, null: false
    t.string :checksum
    t.datetime :created_at, null: false
    t.index :key, unique: true
  end

  create_table :active_storage_attachments, force: :cascade do |t|
    t.string :name, null: false
    t.references :record, null: false, polymorphic: true, index: false, type: :uuid
    t.references :blob, null: false
    t.datetime :created_at, null: false
    t.index %i[record_type record_id name blob_id], name: :index_active_storage_attachments_uniqueness, unique: true
  end

  create_table :active_storage_variant_records, force: :cascade do |t|
    t.belongs_to :blob, null: false, index: false
    t.string :variation_digest, null: false
    t.index %i[blob_id variation_digest], name: :index_active_storage_variant_records_uniqueness, unique: true
  end
end
