# frozen_string_literal: true

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

    # @return [Boolean] whether to cache the generated spec
    attr_accessor :cache_enabled

    # @return [String] the cache key for storing the spec
    attr_accessor :cache_key

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
      @cache_enabled = !Rails.env.development?
      @cache_key = "open_api_generator/open_api"
      @cache_ttl = 10.minutes
      @default_response_description = "OK"
    end
  end
end
