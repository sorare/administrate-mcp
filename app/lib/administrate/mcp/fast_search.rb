# frozen_string_literal: true

module Administrate
  module MCP
    # Administrate's Search with exact matching by default: `*` is the only wildcard, so an id or a
    # slug does not accidentally match every row that contains it.
    class FastSearch < Administrate::Search
      PRIMARY_COLUMN_NAMES = %i[id slug].freeze

      def query_template
        return '' if term.blank?

        search_attributes.map { |attr| attribute_template(attr) }.join(' OR ')
      end

      def operator
        exact_term.include?('%') ? 'LIKE' : '='
      end

      def query_values
        [exact_term] * search_attributes.sum { |attr| searchable_fields(attr).count }
      end

      def exact_term
        term.downcase.tr('*', '%').presence || '%'
      end

      private

      def attribute_template(attr)
        table_name = query_table_name(attr)
        searchable_fields(attr).map { |field| field_template(table_name, field) }.join(' OR ')
      end

      def field_template(table_name, field)
        column_name = column_to_query(field)
        return "LOWER(CAST(#{table_name}.#{column_name} AS TEXT)) #{operator} ?" unless primary?(field)

        "CAST(#{table_name}.#{column_name} AS TEXT) #{operator} ?"
      end

      def primary?(field)
        PRIMARY_COLUMN_NAMES.include?(field)
      end
    end
  end
end
