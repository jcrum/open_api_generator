# frozen_string_literal: true

module OpenApiGenerator
  module ResponseBuilder
    def self.build(config, controller_class, action, docs, registry)
      return docs[:responses] if docs[:responses]

      response = response_spec(controller_class, action)
      return { "200" => { description: config.default_response_description } } unless response

      status = response[:status].to_s
      result = { description: response[:description] || config.default_response_description }
      reference = body_schema(config, controller_class, response, registry)
      result[:content] = { "application/json" => { schema: reference } } if reference

      { status => result }
    end

    def self.response_spec(controller_class, action)
      return unless controller_class.respond_to?(:open_api_generator_response_specs)

      controller_class.open_api_generator_response_specs[action.to_s]
    end

    # Registers the response schema(s) and returns the reference for the body, or nil.
    def self.body_schema(config, controller_class, response, registry)
      name = schema_name(response)
      if envelope(controller_class, response) == :data
        item = item_schema(config, response)
        return unless item

        item_reference = registry.register(name, item)
        return registry.register("#{name}Envelope", { type: "object", properties: { data: item_reference }, required: [ "data" ] }) unless response[:collection]

        return registry.register(
          "#{name}ListEnvelope",
          # `meta` is optional: endpoints that do not paginate omit it.
          { type: "object", properties: { data: { type: "array", items: item_reference }, meta: { type: "object" } }, required: [ "data" ] }
        )
      end

      serializer = response[:serializer]
      if response[:collection] && serializer.respond_to?(:open_api_collection_schema)
        return registry.register("#{name}Collection", serializer.open_api_collection_schema)
      end

      schema = item_schema(config, response)
      return unless schema

      reference = registry.register(name, schema)
      response[:collection] ? { type: "array", items: reference } : reference
    end

    def self.envelope(controller_class, response)
      value = response[:envelope]
      value ||= controller_class.open_api_generator_response_envelope if controller_class.respond_to?(:open_api_generator_response_envelope)
      unless value.nil? || ControllerDSL::ClassMethods::ENVELOPES.include?(value)
        raise ArgumentError, "open_api_generator_response_envelope must be nil, :data or :none, got #{value.inspect}"
      end

      value == :data ? :data : :none
    end

    def self.item_schema(config, response)
      serializer = response[:serializer]
      return serializer.open_api_schema if serializer&.respond_to?(:open_api_schema)
      return model_schema(config, response[:model]) if response[:model]

      nil
    end

    # The legacy model fallback: every column except those the host denylisted.
    def self.model_schema(config, model)
      return ModelSchema.schema_for(model, config: config) unless model.respond_to?(:columns_hash)

      denied = model.columns_hash.keys.select { |column| config.response_column_denied?(column) }
      ModelSchema.schema_for(model, except: denied, config: config)
    end

    # Kept for callers of the previous signature.
    def self.schema_for(response, config: OpenApiGenerator.config)
      item_schema(config, response)
    end

    def self.schema_name(response)
      source = response[:model] || response[:serializer]
      name = source.respond_to?(:name) ? source.name : nil
      name = name.to_s.gsub("::", "").sub(/Serializer$/, "")
      name = "Response" if name.empty?
      name
    end
  end
end
