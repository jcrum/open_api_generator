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

    # @param path_keys [Array<Symbol,String>] route path parameter names. When the body is
    #   flat (no wrapper), these are ignored for required enforcement so a path segment
    #   cannot satisfy a body field of the same name.
    def permit(params, path_keys: [])
      source = wrapped_in ? (params[wrapped_in] || params) : params
      raise ActionController::ParameterMissing, wrapped_in if wrapped_in && !source.is_a?(ActionController::Parameters)

      permitted = source.permit(*permit_filters(fields)).to_h.deep_symbolize_keys
      if OpenApiGenerator.config.enforce_required
        body = source.equal?(params) ? source.except(*path_keys.map(&:to_s)).permit(*permit_filters(fields)).to_h.deep_symbolize_keys : permitted
        enforce_required!(body)
      end
      permitted
    end

    def schema
      object_schema(fields)
    end

    def schema_name(controller_class: nil)
      base = if model
        model.name.to_s.gsub("::", "")
      elsif controller_class
        controller_class.name.to_s.split("::").last.to_s.sub(/Controller\z/, "")
      else
        action.classify
      end
      "#{base}#{action.classify}Request"
    end

    private

    # A trailing `!` on a Hash or Array-of-Hash key marks the nested object (or the
    # array of objects) itself required: `"actor!": { kind: :string! }`.
    def parse(name, token)
      name = name.to_s
      required = name.end_with?("!")
      name = name.chomp("!")

      if token.is_a?(Hash)
        Field.new(
          name: name,
          type: :object,
          array: false,
          required: required,
          children: token.map { |child_name, child_token| parse(child_name, child_token) },
          array_children: nil
        )
      elsif token.is_a?(Array)
        inner = token.first
        if inner.is_a?(Array) && inner.length == 1 && inner.first.is_a?(Hash)
          children = inner.first
          Field.new(name: name, type: :object, array: true, required: required, children: nil,
            array_children: children.map { |child_name, child_token| parse(child_name, child_token) })
        elsif inner.is_a?(Hash)
          Field.new(name: name, type: :object, array: true, required: required, children: nil,
            array_children: inner.map { |child_name, child_token| parse(child_name, child_token) })
        else
          value = inner.to_s
          Field.new(name: name, type: value.chomp("!").to_sym, array: true, required: required || value.end_with?("!"), children: nil, array_children: nil)
        end
      else
        value = token.to_s
        Field.new(name: name, type: value.chomp("!").to_sym, array: false, required: required || value.end_with?("!"), children: nil, array_children: nil)
      end
    end

    # Raises ParameterMissing for the first top-level required field that is absent
    # or nil in the permitted output (so a wrong-shaped value that permit drops counts
    # as missing). `false` and "" are present values and reach the model.
    def enforce_required!(permitted)
      fields.each do |field|
        next unless field.required

        raise ActionController::ParameterMissing, field.name if permitted[field.name.to_sym].nil?
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

    def object_schema(list)
      result = { type: "object", properties: list.each_with_object({}) { |field, properties| properties[field.name] = field_schema(field) } }
      required = list.select(&:required).map(&:name)
      result[:required] = required if required.any?
      result
    end

    def field_schema(field)
      if field.array_object?
        { type: "array", items: object_schema(field.array_children) }
      elsif field.object?
        object_schema(field.children)
      elsif field.array?
        TypeMapper.array(field.type)
      else
        column_or_scalar(field)
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
