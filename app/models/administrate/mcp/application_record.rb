# frozen_string_literal: true

module Administrate
  module MCP
    # Base class for the engine's own tables.
    class ApplicationRecord < ActiveRecord::Base
      self.abstract_class = true

      class << self
        def belongs_to_admin
          belongs_to :admin, class_name: Administrate::MCP.config.admin_class_name, optional: false
        end
      end
    end
  end
end
