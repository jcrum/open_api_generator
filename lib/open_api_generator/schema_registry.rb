# frozen_string_literal: true

module OpenApiGenerator
  class SchemaRegistry
    def initialize
      @schemas = {}
    end

    def register(name, schema)
      if @schemas.key?(name) && @schemas[name] != schema
        raise ArgumentError, "schema #{name} was registered with different definitions"
      end

      @schemas[name] ||= schema
      { "$ref" => "#/components/schemas/#{name}" }
    end

    def to_h
      @schemas
    end
  end
end
