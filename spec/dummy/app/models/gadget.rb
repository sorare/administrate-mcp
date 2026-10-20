# frozen_string_literal: true

class Gadget < ApplicationRecord
  belongs_to :widget
  has_one_attached :manual
end
