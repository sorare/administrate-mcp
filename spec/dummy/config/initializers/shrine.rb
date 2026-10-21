# frozen_string_literal: true

Shrine.storages = { cache: Shrine::Storage::Memory.new, store: Shrine::Storage::Memory.new }
Shrine.plugin :activerecord
Shrine.plugin :determine_mime_type, analyzer: :marcel
