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

    def self.scalar(type)
      SCALARS.fetch(type.to_sym, { type: "string" }).dup
    end

    def self.array(inner_type)
      { type: "array", items: scalar(inner_type) }
    end
  end
end
