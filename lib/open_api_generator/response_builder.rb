# frozen_string_literal: true

module OpenApiGenerator
  module ResponseBuilder
    def self.build(config, controller_class, action, docs, registry)
      return docs[:responses] if docs[:responses]

      response = response_spec(controller_class, action)
      return { "200" => { description: config.default_response_description } } unless response

      status = response[:status].to_s
      result = { description: response[:description] || config.default_response_description }
      schema = schema_for(response)
      if schema
        reference = registry.register(schema_name(response), schema)
        reference = { type: "array", items: reference } if response[:collection]
        result[:content] = { "application/json" => { schema: reference } }
      end

      { status => result }
    end

    def self.response_spec(controller_class, action)
      return unless controller_class.respond_to?(:open_api_generator_response_specs)

      controller_class.open_api_generator_response_specs[action.to_s]
    end

    def self.schema_for(response)
      serializer = response[:serializer]
      return serializer.open_api_schema if serializer&.respond_to?(:open_api_schema)
      return ModelSchema.schema_for(response[:model]) if response[:model]

      nil
    end

    def self.schema_name(response)
      source = response[:model] || response[:serializer]
      name = source.respond_to?(:name) ? source.name : nil
      name = name.to_s.demodulize.sub(/Serializer$/, "")
      name = "Response" if name.empty?
      name
    end
  end
end
