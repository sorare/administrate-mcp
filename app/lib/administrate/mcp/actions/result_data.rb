# frozen_string_literal: true

module Administrate
  module MCP
    module Actions
      # Reads the `mcp_data` of an action's result and checks it can go back to the client: a Hash of
      # plain JSON values, no larger than `config.action_data_max_bytes` once encoded. The action has
      # already run when this is checked, so the error says so.
      module ResultData
        SCALARS = [String, Symbol, Integer, TrueClass, FalseClass, NilClass].freeze

        class << self
          def extract!(result, tool_name:)
            return nil unless result.respond_to?(:mcp_data)

            data = result.mcp_data
            return nil if data.nil?

            check!(data, tool_name)
            data
          end

          private

          def check!(data, tool_name)
            raise TypeError, "data is #{article(data)} #{data.class}, not a Hash" unless data.is_a?(Hash)

            check_value!(data, 'data')
            check_size!(data)
          rescue TypeError, RangeError => e
            raise Error, "#{tool_name} ran, but its data cannot be returned: #{e.message}"
          end

          def check_value!(value, path)
            case value
            when Hash then value.each { |key, item| check_value!(item, "#{path}.#{key_name!(key, path)}") }
            when Array then value.each_with_index { |item, index| check_value!(item, "#{path}[#{index}]") }
            else check_scalar!(value, path)
            end
          end

          def check_scalar!(value, path)
            raise TypeError, "#{path} is not a finite number" if value.is_a?(Float) && !value.finite?
            return if value.is_a?(Float) || SCALARS.any? { |type| value.is_a?(type) }

            raise TypeError, "#{path} is #{article(value)} #{value.class}, not a JSON value"
          end

          def key_name!(key, path)
            return key.to_s if key.is_a?(String) || key.is_a?(Symbol)

            raise TypeError, "#{path} has #{article(key)} #{key.class} key, not a String or Symbol"
          end

          def check_size!(data)
            limit = Administrate::MCP.config.action_data_max_bytes
            return if limit.nil?

            bytes = data.to_json.bytesize
            return if bytes <= limit

            raise RangeError,
                  "data is #{bytes} bytes of JSON, over the #{limit}-byte limit (config.action_data_max_bytes)"
          end

          def article(value)
            value.class.name.match?(/\A[AEIOU]/) ? 'an' : 'a'
          end
        end
      end
    end
  end
end
