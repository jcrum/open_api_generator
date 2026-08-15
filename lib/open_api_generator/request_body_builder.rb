# frozen_string_literal: true

module OpenApiGenerator
  module RequestBodyBuilder
    def self.build(controller_class, action, docs, registry)
      return docs[:requestBody] if docs[:requestBody]

      spec = input_spec(controller_class, action)
      return unless spec

      reference = registry.register(spec.schema_name, spec.schema)
      {
        required: spec.fields.any?(&:required),
        content: { "application/json" => { schema: reference } }
      }
    end

    def self.input_spec(controller_class, action)
      return unless controller_class.respond_to?(:open_api_generator_input_specs)

      controller_class.open_api_generator_input_specs[action.to_s]
    end
  end
end
