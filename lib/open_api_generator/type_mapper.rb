# frozen_string_literal: true

module OpenApiGenerator
  module TypeMapper
    SCALARS = {
      string: { type: "string" },
      text: { type: "string" },
      integer: { type: "integer" },
      bigint: { type: "integer" },
      float: { type: "number" },
      decimal: { type: "number" },
      boolean: { type: "boolean" },
      date: { type: "string", format: "date" },
      datetime: { type: "string", format: "date-time" },
      timestamp: { type: "string", format: "date-time" },
      uuid: { type: "string", format: "uuid" },
      email: { type: "string", format: "email" },
      json: { type: "object" },
      jsonb: { type: "object" }
    }.freeze

    # @param config [Configuration] source of `scalar_overrides` (the one passed to
    #   `SpecBuilder.call(config:)`, defaulting to the global)
    def self.scalar(type, config = OpenApiGenerator.config)
      key = type.to_sym
      override = config.scalar_overrides[key]
      (override || SCALARS.fetch(key, { type: "string" })).dup
    end

    def self.array(inner_type, config = OpenApiGenerator.config)
      { type: "array", items: scalar(inner_type, config) }
    end
  end
end
