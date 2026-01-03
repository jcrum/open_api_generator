# frozen_string_literal: true

module OpenApiGenerator
  # Generates OpenAPI schema objects from ActiveRecord models.
  #
  # This helper can be used to generate schemas for request/response bodies
  # based on model column definitions.
  #
  # @example Generate schema for all columns
  #   ModelSchema.schema_for(User)
  #   # => { type: "object", properties: { id: { type: "integer" }, ... } }
  #
  # @example Generate schema for specific columns
  #   ModelSchema.schema_for(User, only_columns: ["name", "email"])
  class ModelSchema
    # Generates an OpenAPI schema object for a model.
    #
    # @param model_class [Class] the ActiveRecord model class
    # @param only_columns [Array<String>, nil] optional array of column names to include
    # @return [Hash] an OpenAPI schema object
    def self.schema_for(model_class, only_columns: nil)
      return { type: "object" } unless model_class
      return { type: "object" } unless model_class.respond_to?(:columns_hash)

      columns = select_columns(model_class.columns_hash, only_columns)
      properties = {}
      required = []

      columns.each do |column_name, column|
        properties[column_name] = column_schema(column, model_class, column_name)
        required << column_name unless column.null
      end

      schema = { type: "object", properties: properties }
      schema[:required] = required if required.any?
      schema
    end

    # Selects columns based on the only_columns filter.
    #
    # @param columns_hash [Hash] the model's columns_hash
    # @param only_columns [Array<String>, nil] optional array of column names to include
    # @return [Hash] filtered columns hash
    def self.select_columns(columns_hash, only_columns)
      return columns_hash unless only_columns

      columns_hash.select { |name, _| only_columns.include?(name.to_s) }
    end

    # Generates an OpenAPI schema for a single column.
    #
    # @param column [ActiveRecord::ConnectionAdapters::Column] the column object
    # @param model_class [Class] the model class
    # @param column_name [String] the column name
    # @return [Hash] an OpenAPI schema object for the column
    def self.column_schema(column, model_class, column_name)
      if enum_column?(model_class, column_name)
        return enum_schema(model_class, column_name)
      end

      type_schema(column.type)
    end

    # Checks if a column is an enum.
    #
    # @param model_class [Class] the model class
    # @param column_name [String] the column name
    # @return [Boolean] true if the column is an enum
    def self.enum_column?(model_class, column_name)
      model_class.respond_to?(:defined_enums) &&
        model_class.defined_enums.key?(column_name.to_s)
    end

    # Generates an OpenAPI schema for an enum column.
    #
    # @param model_class [Class] the model class
    # @param column_name [String] the column name
    # @return [Hash] an OpenAPI schema object with enum values
    def self.enum_schema(model_class, column_name)
      {
        type: "string",
        enum: model_class.defined_enums[column_name.to_s].keys
      }
    end

    # Maps a column type to an OpenAPI schema type.
    #
    # @param column_type [Symbol] the column type from ActiveRecord
    # @return [Hash] an OpenAPI schema object
    def self.type_schema(column_type)
      case column_type
      when :integer, :bigint
        { type: "integer" }
      when :float, :decimal
        { type: "number" }
      when :boolean
        { type: "boolean" }
      when :datetime, :timestamp
        { type: "string", format: "date-time" }
      when :date
        { type: "string", format: "date" }
      when :json, :jsonb
        { type: "object" }
      else
        { type: "string" }
      end
    end
  end
end
