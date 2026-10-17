# frozen_string_literal: true

require "digest"

module OpenApiGenerator
  # Configuration for OpenAPI spec generation.
  #
  # @example
  #   OpenApiGenerator.configure do |config|
  #     config.title = "My API"
  #     config.version = "1.0.0"
  #     config.servers = [{ url: "https://api.example.com" }]
  #   end
  class Configuration
    DEFAULT_CACHE_KEY = "open_api_generator/open_api"

    # @return [String] the title of the API (appears in OpenAPI info section)
    attr_accessor :title

    # @return [String] the version of the API (appears in OpenAPI info section)
    attr_accessor :version

    # @return [String, nil] the description of the API (appears in OpenAPI info section)
    attr_accessor :description

    # @return [Array<Hash>] array of server objects (e.g., [{url: "https://api.example.com"}])
    attr_accessor :servers

    # @return [Array<Regexp>] array of regex patterns for paths to ignore
    attr_accessor :ignored_paths

    # @return [Array<String>] array of controller class names to ignore
    attr_accessor :ignored_controllers

    # @return [Hash] OpenAPI security scheme definitions
    attr_accessor :security_schemes

    # @return [Array<Hash>, nil] top-level OpenAPI security requirements
    attr_accessor :security

    # @return [Array<String>] base controller names whose descendants are included
    attr_accessor :included_base_controllers

    # @return [Boolean] whether to cache the generated spec
    attr_accessor :cache_enabled

    # @return [String, nil] explicit cache key override; when nil, #cache_key derives one
    attr_writer :cache_key

    # @return [#call, nil] callable taking the OpenApiController instance. A falsy
    #   result answers 404 with an empty body for spec.json, spec.yaml and routes.json
    #   before any cache read or build. nil (the default) leaves the docs public.
    attr_reader :authorize

    # @param callable [#call, nil]
    # @raise [ArgumentError] unless nil or callable
    def authorize=(callable)
      raise ArgumentError, "authorize must be nil or respond to #call" unless callable.nil? || callable.respond_to?(:call)

      @authorize = callable
    end

    # @return [Boolean] when true, `permitted` raises ActionController::ParameterMissing
    #   for a top-level `!` field whose key is missing or nil (`false` and "" pass).
    #   Default false: `!` is schema-only. Nested `!` fields are never enforced.
    attr_reader :enforce_required

    # @param value [Boolean]
    # @raise [ArgumentError] unless true or false
    def enforce_required=(value)
      raise ArgumentError, "enforce_required must be true or false" unless value == true || value == false

      @enforce_required = value
    end

    # @return [ActiveSupport::Duration] how long to cache the spec
    attr_accessor :cache_ttl

    # @return [String] default description for responses when none is provided
    attr_accessor :default_response_description

    # Initializes a new Configuration with default values.
    def initialize
      @title = "API"
      @version = "1.0.0"
      @description = nil
      @servers = [{ url: "/" }]
      @ignored_paths = [%r{^/rails}]
      @ignored_controllers = []
      @security_schemes = {}
      @security = nil
      @included_base_controllers = []
      @cache_enabled = !Rails.env.development?
      @cache_key = nil
      @authorize = nil
      @enforce_required = false
      @cache_ttl = 10.minutes
      @default_response_description = "OK"
    end

    # The cache key for the generated spec. A host override is used verbatim.
    # Otherwise the key carries a discriminator: `Rails.application.config.x.release`
    # when the host sets it (recommended: the deploy revision), else a digest of
    # the discovered routes (verb, path, controller, action only). The digest does
    # not change when only `swagger`, `api_params`, `api_response` or serializers
    # change, so without `x.release` such a deploy can serve the previous spec
    # for up to `cache_ttl`.
    #
    # @return [String]
    def cache_key
      @cache_key || "#{DEFAULT_CACHE_KEY}/#{cache_discriminator}"
    end

    private

    def cache_discriminator
      release = Rails.application.config.x.release.presence
      return Digest::SHA256.hexdigest(release.to_s)[0, 16] if release

      route_digest
    end

    def route_digest
      size = Rails.application.routes.routes.size
      return @route_digest if @route_digest && @route_digest_size == size

      lines = RouteDiscovery.call(config: self).map { |r| [r.verb, r.path, r.controller, r.action].join(" ") }
      digest = Digest::SHA256.hexdigest(lines.sort.join("\n"))[0, 16]
      @route_digest = digest
      @route_digest_size = size
      digest
    end
  end
end
