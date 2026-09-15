# frozen_string_literal: true

class Admin < ApplicationRecord
  has_many :widgets, dependent: :nullify

  def can_access?(*roles)
    roles.flatten.map(&:to_s).include?(role)
  end
end
