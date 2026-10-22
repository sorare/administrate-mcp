# frozen_string_literal: true

module Administrate
  module MCP
    module Actions
      # Reads the `mcp_data` of an action's result and turns it into what goes back to the client: a
      # copy built only from plain Hashes with String keys, Arrays, Strings and JSON scalars, no deeper
      # than MAX_DEPTH and no larger than `config.action_data_max_bytes` once encoded. The copy, not
      # the host's objects, is what gets encoded, so no `as_json` of theirs runs. The action has
      # already run when this is checked, so the error says so.
      module ResultData
        MAX_DEPTH = 32

        SCALARS = [Integer, TrueClass, FalseClass, NilClass].freeze

        class << self
          def extract!(result, tool_name:)
            return nil unless result.respond_to?(:mcp_data)

            data = result.mcp_data
            return nil if data.nil?

            normalize_root!(data, tool_name)
          end

          private

          def normalize_root!(data, tool_name)
            raise TypeError, "data (#{data.class}) is not a Hash" unless data.is_a?(Hash)

            normalize!(data, 'data').tap { |copy| check_size!(copy) }
          rescue TypeError, RangeError => e
            raise Error, "#{tool_name} ran, but its data cannot be returned: #{e.message}"
          end

          def normalize!(value, path, depth = 0)
            raise RangeError, "#{path} is nested deeper than #{MAX_DEPTH} levels" if depth > MAX_DEPTH

            case value
            when Hash then normalize_hash!(value, path, depth)
            when Array then value.each_with_index.map { |item, index| normalize!(item, "#{path}[#{index}]", depth + 1) }
            when String, Symbol then String.new(value.to_s)
            else normalize_scalar!(value, path)
            end
          end

          def normalize_hash!(hash, path, depth)
            hash.each_with_object({}) do |(key, item), copy|
              name = key_name!(key, path)
              raise TypeError, "#{path} has the key #{name} twice" if copy.key?(name)

              copy[name] = normalize!(item, "#{path}.#{name}", depth + 1)
            end
          end

          def key_name!(key, path)
            return String.new(key.to_s) if key.is_a?(String) || key.is_a?(Symbol)

            raise TypeError, "#{path} has a key (#{key.class}) that is not a String or Symbol"
          end

          def normalize_scalar!(value, path)
            if value.instance_of?(Float)
              raise TypeError, "#{path} is not a finite number" unless value.finite?

              return value
            end
            return value if SCALARS.any? { |type| value.instance_of?(type) }

            raise TypeError, "#{path} (#{value.class}) is not a JSON value"
          end

          def check_size!(copy)
            limit = Administrate::MCP.config.action_data_max_bytes
            return if limit.nil?

            bytes = copy.to_json.bytesize
            return if bytes <= limit

            raise RangeError,
                  "data is #{bytes} bytes of JSON, over the #{limit}-byte limit (config.action_data_max_bytes)"
          end
        end
      end
    end
  end
end
