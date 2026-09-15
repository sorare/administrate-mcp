# frozen_string_literal: true

class Widget < ApplicationRecord
  belongs_to :admin, optional: true
  has_many :gadgets, dependent: :destroy

  enum :status, { draft: 0, published: 1, archived: 2 }

  default_scope { where.not(status: :archived) }
end
