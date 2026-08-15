# frozen_string_literal: true

require "open_api_generator/engine"
require "open_api_generator/configuration"
require "open_api_generator/controller_dsl"
require "open_api_generator/route_discovery"
require "open_api_generator/type_mapper"
require "open_api_generator/input_spec"
require "open_api_generator/schema_registry"
require "open_api_generator/request_body_builder"
require "open_api_generator/response_builder"
require "open_api_generator/completeness"
require "open_api_generator/model_schema"
require "open_api_generator/spec_builder"

# OpenApiGenerator generates OpenAPI 3.0 documentation from Rails routes and controllers.
#
# @example Basic configuration
#   OpenApiGenerator.configure do |c|
#     c.title = "My API"
#     c.version = "1.0.0"
#   end
module OpenApiGenerator
  class << self
    # Returns the current configuration instance.
    #
    # @return [Configuration] the configuration object
    def config
      @config ||= Configuration.new
    end

    # Configures OpenApiGenerator with a block.
    #
    # @yield [Configuration] the configuration object
    # @example
    #   OpenApiGenerator.configure do |c|
    #     c.title = "My API"
    #     c.version = "1.0.0"
    #   end
    def configure
      yield(config)
    end
  end
end

OpenApiGenerator = OpenApiGenerator unless defined?(OpenApiGenerator)
