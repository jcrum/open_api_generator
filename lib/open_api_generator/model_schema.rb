# frozen_string_literal: true

module OpenApiGenerator
  class ModelSchema
    DEFAULT_EXCLUDED_COLUMNS = %w[id created_at updated_at].freeze

    def self.schema_for(model_class, only_columns: nil, writable: false, except: [], required: nil, arrays: [])
      return { type: "object" } unless model_class&.respond_to?(:columns_hash)

      columns = select_columns(model_class.columns_hash, only_columns)
      excluded = writable ? DEFAULT_EXCLUDED_COLUMNS : []
      excluded += columns.keys.select { |name| name.to_s.end_with?("_count") }
      excluded += Array(except).map(&:to_s)
      columns = columns.reject { |name, _| excluded.include?(name.to_s) }
      array_columns = Array(arrays).map(&:to_s)

      properties = {}
      inferred_required = []
      columns.each do |column_name, column|
        properties[column_name] = if array_columns.include?(column_name.to_s)
          TypeMapper.array(column.type)
        else
          column_schema(column, model_class, column_name)
        end
        inferred_required << column_name unless column.null
      end

      schema = { type: "object", properties: properties }
      required_columns = required.nil? ? inferred_required : Array(required).map(&:to_s)
      schema[:required] = required_columns if required_columns.any?
      schema
    end

    def self.select_columns(columns_hash, only_columns)
      return columns_hash unless only_columns

      columns_hash.select { |name, _| only_columns.map(&:to_s).include?(name.to_s) }
    end

    def self.column_schema(column, model_class, column_name)
      return enum_schema(model_class, column_name) if enum_column?(model_class, column_name)

      TypeMapper.scalar(column.type)
    end

    def self.enum_column?(model_class, column_name)
      model_class.respond_to?(:defined_enums) && model_class.defined_enums.key?(column_name.to_s)
    end

    def self.enum_schema(model_class, column_name)
      { type: "string", enum: model_class.defined_enums[column_name.to_s].keys }
    end

    def self.type_schema(column_type)
      TypeMapper.scalar(column_type)
    end
  end
end
