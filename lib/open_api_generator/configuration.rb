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

    # @return [Array<String, Regexp>] column names (strings) or patterns (Regexp) left out of
    #   response schemas built by the model fallback in `api_response model:`. Serializer
    #   schemas and request schemas (`api_params`) are never filtered. Default `[]`.
    attr_reader :response_column_denylist

    # @param value [Array<String, Regexp>, String, Regexp, nil]
    # @raise [ArgumentError] unless every entry is a String, Symbol or Regexp
    def response_column_denylist=(value)
      entries = Array(value)
      unless entries.all? { |entry| entry.is_a?(String) || entry.is_a?(Symbol) || entry.is_a?(Regexp) }
        raise ArgumentError, "response_column_denylist entries must be Strings or Regexps"
      end

      @response_column_denylist = entries.map { |entry| entry.is_a?(Symbol) ? entry.to_s : entry }.freeze
    end

    # @param column_name [String, Symbol]
    # @return [Boolean] whether the denylist hides this column from model response schemas
    def response_column_denied?(column_name)
      name = column_name.to_s
      response_column_denylist.any? { |entry| entry.is_a?(Regexp) ? entry.match?(name) : entry == name }
    end

    # @return [ActiveSupport::Duration] how long to cache the spec
    attr_accessor :cache_ttl

    # @return [String] default description for responses when none is provided
    attr_accessor :default_response_description

    # @return [Hash{Symbol=>Hash}] per-type schema overrides consulted before the
    #   built-in scalar map (for example `{ uuid: { type: "string", pattern: "..." } }`).
    #   Keys are symbols; the hash and its values are deeply frozen.
    attr_reader :scalar_overrides

    # Replaces the scalar overrides. Keys are symbolized and the result is frozen.
    #
    # @param overrides [Hash]
    def scalar_overrides=(overrides)
      @scalar_overrides = deep_freeze((overrides || {}).to_h { |type, schema| [ type.to_sym, schema.deep_dup ] })
    end

    # Initializes a new Configuration with default values.
    def initialize
      @title = "API"
      @version = "1.0.0"
      @description = nil
      @servers = [ { url: "/" } ]
      @ignored_paths = [ %r{^/rails} ]
      @ignored_controllers = []
      @security_schemes = {}
      @security = nil
      @included_base_controllers = []
      @cache_enabled = !Rails.env.development?
      @cache_key = nil
      @authorize = nil
      @enforce_required = false
      @response_column_denylist = [].freeze
      @cache_ttl = 10.minutes
      @default_response_description = "OK"
      @scalar_overrides = {}.freeze
    end

    # The cache key for the generated spec. A host override is used verbatim.
    # Otherwise the key carries a discriminator: a digest of the release marker (when
    # present) joined with a digest of the discovered routes (verb, path, controller,
    # action only). The route digest does
    # not change when only `swagger`, `api_params`, `api_response` or serializers
    # change, so without a release marker such a deploy can serve the previous spec
    # for up to `cache_ttl`. The release marker is `x.release`, else the `KAMAL_VERSION`
    # environment variable that Kamal sets on deploy.
    #
    # @return [String]
    def cache_key
      @cache_key || "#{DEFAULT_CACHE_KEY}/#{cache_discriminator}"
    end

    private

    def deep_freeze(value)
      case value
      when Hash then value.each { |k, v| deep_freeze(k); deep_freeze(v) }
      when Array then value.each { |v| deep_freeze(v) }
      end
      value.freeze
    end

    def cache_discriminator
      release = Rails.application.config.x.release.presence || ENV["KAMAL_VERSION"].presence
      Digest::SHA256.hexdigest([ release, route_digest ].compact.join("/"))[0, 16]
    end

    def route_digest
      size = Rails.application.routes.routes.size
      return @route_digest if @route_digest && @route_digest_size == size

      lines = RouteDiscovery.call(config: self).map { |r| [ r.verb, r.path, r.controller, r.action ].join(" ") }
      digest = Digest::SHA256.hexdigest(lines.sort.join("\n"))[0, 16]
      @route_digest = digest
      @route_digest_size = size
      digest
    end
  end
end
