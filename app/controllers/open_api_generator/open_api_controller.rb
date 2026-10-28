# frozen_string_literal: true

module OpenApiGenerator
  # Controller that serves the OpenAPI specification.
  #
  # Mounted at /spec.json and /spec.yaml by default.
  class OpenApiController < ActionController::Base
    RACE_CONDITION_TTL = 30.seconds

    # Runs before the cache read or the build. A falsy `config.authorize`
    # answer is a bare 404 so the docs never confirm they exist.
    before_action :authorize_docs!

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

    def authorize_docs!
      authorizer = OpenApiGenerator.config.authorize
      return if authorizer.nil?

      head :not_found unless authorizer.call(self)
    end

    # Builds or retrieves the cached OpenAPI spec.
    #
    # @return [Hash] the OpenAPI specification
    def spec
      cfg = OpenApiGenerator.config
      with_cache(cfg, key: -> { cfg.cache_key }) { OpenApiGenerator::SpecBuilder.call(config: cfg) }
    end

    def route_introspection
      cfg = OpenApiGenerator.config
      with_cache(cfg, key: -> { "#{cfg.cache_key}/routes" }) { OpenApiGenerator::SpecBuilder.route_introspection(config: cfg) }
    end

    def with_cache(config, key:)
      return yield unless config.cache_enabled

      Rails.cache.fetch(key.call, expires_in: config.cache_ttl, race_condition_ttl: RACE_CONDITION_TTL) { yield }
    end
  end
end
