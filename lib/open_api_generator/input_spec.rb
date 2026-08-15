# frozen_string_literal: true

module OpenApiGenerator
  class InputSpec
    Field = Struct.new(:name, :type, :array, :required, keyword_init: true) do
      def array?
        array
      end
    end

    attr_reader :action, :wrapped_in, :model, :fields

    def initialize(action:, permit:, wrapped_in: nil, model: nil)
      @action = action.to_s
      @wrapped_in = wrapped_in
      @model = model
      @fields = permit.map { |name, token| parse(name, token) }
    end

    def permit(params)
      source = wrapped_in ? (params[wrapped_in] || params) : params
      scalars = fields.reject(&:array?).map { |field| field.name.to_sym }
      arrays = fields.select(&:array?).each_with_object({}) { |field, result| result[field.name.to_sym] = [] }
      source.permit(*scalars, arrays).to_h.symbolize_keys
    end

    def schema
      properties = {}
      required = []

      fields.each do |field|
        properties[field.name] = if field.array?
          TypeMapper.array(field.type)
        else
          column_or_scalar(field)
        end
        required << field.name if field.required
      end

      result = { type: "object", properties: properties }
      result[:required] = required if required.any?
      result
    end

    def schema_name
      base = model ? model.name.demodulize : action.classify
      "#{base}#{action.classify}Request"
    end

    private

    def parse(name, token)
      if token.is_a?(Array)
        inner = token.first.to_s
        Field.new(name: name.to_s, type: inner.chomp("!").to_sym, array: true, required: inner.end_with?("!"))
      else
        value = token.to_s
        Field.new(name: name.to_s, type: value.chomp("!").to_sym, array: false, required: value.end_with?("!"))
      end
    end

    def column_or_scalar(field)
      if model&.respond_to?(:defined_enums) && model.defined_enums.key?(field.name)
        { type: "string", enum: model.defined_enums[field.name].keys }
      else
        TypeMapper.scalar(field.type)
      end
    end
  end
end
