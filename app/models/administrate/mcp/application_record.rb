# frozen_string_literal: true

module Administrate
  module MCP
    # Base class for the engine's own tables.
    class ApplicationRecord < ActiveRecord::Base
      self.abstract_class = true

      class << self
        # `isolate_namespace` strips the namespace from model_name, so ApiKey would answer
        # `api_keys` and collide with the host's own resource of that name in route and form
        # helpers. These records name themselves the way any other namespaced model does.
        def model_name
          @model_name ||= ActiveModel::Name.new(self, nil, name)
        end

        def belongs_to_admin
          belongs_to :admin, class_name: Administrate::MCP.config.admin_class_name,
                             foreign_key: Administrate::MCP.config.admin_foreign_key,
                             inverse_of: false,
                             optional: false
        end
      end
    end
  end
end
