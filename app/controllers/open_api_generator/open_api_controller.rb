# frozen_string_literal: true

module OpenApiGenerator
  # Controller that serves the OpenAPI specification.
  #
  # Mounted at /spec.json and /spec.yaml by default.
  class OpenApiController < ActionController::Base
    RACE_CONDITION_TTL = 30.seconds

    # Renders the OpenAPI spec as JSON.
    #
    # @return [void]
    def json
      render json: spec
    end

    # Renders the OpenAPI spec as YAML.
    #
    # @return [void]
    def yaml
      render plain: spec.to_yaml, content_type: "application/yaml"
    end

    # Renders the routes introspection payload as JSON.
    #
    # @return [void]
    def routes
      return head :not_found unless Rails.env.development?

      render json: route_introspection
    end

    private

    # Builds or retrieves the cached OpenAPI spec.
    #
    # @return [Hash] the OpenAPI specification
    def spec
      cfg = OpenApiGenerator.config

      if cfg.cache_enabled
        Rails.cache.fetch(cfg.cache_key, expires_in: cfg.cache_ttl, race_condition_ttl: RACE_CONDITION_TTL) do
          OpenApiGenerator::SpecBuilder.call(config: cfg)
        end
      else
        OpenApiGenerator::SpecBuilder.call(config: cfg)
      end
    end

    def route_introspection
      cfg = OpenApiGenerator.config

      if cfg.cache_enabled
        Rails.cache.fetch("#{cfg.cache_key}/routes", expires_in: cfg.cache_ttl, race_condition_ttl: RACE_CONDITION_TTL) do
          OpenApiGenerator::SpecBuilder.route_introspection(config: cfg)
        end
      else
        OpenApiGenerator::SpecBuilder.route_introspection(config: cfg)
      end
    end
  end
end
