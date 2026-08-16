# frozen_string_literal: true

module OpenApiGenerator
  class InputSpec
    Field = Struct.new(:name, :type, :array, :required, :children, :array_children, keyword_init: true) do
      def array?
        array
      end

      def object?
        children.present?
      end

      def array_object?
        array? && array_children.present?
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
      source.permit(*permit_filters(fields)).to_h.deep_symbolize_keys
    end

    def schema
      properties = {}
      required = []

      fields.each do |field|
        properties[field.name] = if field.array_object?
          { type: "array", items: { type: "object", properties: schema_properties(field.array_children) } }
        elsif field.object?
          { type: "object", properties: schema_properties(field.children) }
        elsif field.array?
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
      if token.is_a?(Hash)
        Field.new(
          name: name.to_s,
          type: :object,
          array: false,
          required: false,
          children: token.map { |child_name, child_token| parse(child_name, child_token) },
          array_children: nil
        )
      elsif token.is_a?(Array)
        inner = token.first
        if inner.is_a?(Array) && inner.length == 1 && inner.first.is_a?(Hash)
          children = inner.first
          Field.new(name: name.to_s, type: :object, array: true, required: false, children: nil,
            array_children: children.map { |child_name, child_token| parse(child_name, child_token) })
        elsif inner.is_a?(Hash)
          Field.new(name: name.to_s, type: :object, array: true, required: false, children: nil,
            array_children: inner.map { |child_name, child_token| parse(child_name, child_token) })
        else
          value = inner.to_s
          Field.new(name: name.to_s, type: value.chomp("!").to_sym, array: true, required: value.end_with?("!"), children: nil, array_children: nil)
        end
      else
        value = token.to_s
        Field.new(name: name.to_s, type: value.chomp("!").to_sym, array: false, required: value.end_with?("!"), children: nil, array_children: nil)
      end
    end

    def permit_filters(list)
      list.map do |field|
        if field.array_object?
          { field.name.to_sym => permit_filters(field.array_children) }
        elsif field.object?
          { field.name.to_sym => permit_filters(field.children) }
        elsif field.array?
          { field.name.to_sym => [] }
        else
          field.name.to_sym
        end
      end
    end

    def schema_properties(list)
      list.each_with_object({}) do |field, properties|
        properties[field.name] = if field.array_object?
          { type: "array", items: { type: "object", properties: schema_properties(field.array_children) } }
        elsif field.object?
          { type: "object", properties: schema_properties(field.children) }
        elsif field.array?
          TypeMapper.array(field.type)
        else
          column_or_scalar(field)
        end
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
