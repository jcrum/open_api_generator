# frozen_string_literal: true

module OpenApiGenerator
  # Discovers all routes in the Rails application and mounted engines.
  #
  # Routes are discovered from:
  # - Rails.application.routes
  # - All mounted Rails::Engine subclasses (except OpenApiGenerator::Engine itself)
  class RouteDiscovery
    # A simple struct to hold route information.
    #
    # @!attribute verb
    #   @return [String] the HTTP verb (GET, POST, etc.)
    # @!attribute path
    #   @return [String] the path pattern
    # @!attribute controller
    #   @return [String] the controller name
    # @!attribute action
    #   @return [String] the action name
    RouteInfo = Struct.new(:verb, :path, :controller, :action)

    # Discovers all routes in the application and mounted engines.
    #
    # @param config [Configuration] the configuration object
    # @return [Array<RouteInfo>] array of discovered routes
    def self.call(config:)
      all_routes = []
      all_routes.concat(extract_routes(Rails.application.routes.routes, config))

      Rails::Engine.subclasses.each do |engine|
        next if engine == OpenApiGenerator::Engine
        next unless engine.routes.routes.any?

        mount_point = find_engine_mount_point(engine)
        all_routes.concat(extract_routes(engine.routes.routes, config, mount_point))
      end

      all_routes
    end

    # Extracts RouteInfo objects from a collection of Rails routes.
    #
    # @param routes [ActionDispatch::Journey::Routes] the routes to extract from
    # @param config [Configuration] the configuration object
    # @param mount_point [String] optional path prefix to prepend to each route
    # @return [Array<RouteInfo>] array of extracted routes
    def self.extract_routes(routes, config, mount_point = "")
      routes.filter_map do |route|
        next unless route.defaults[:controller] && route.defaults[:action]

        verb = route.verb.gsub("$", "")
        next if verb.empty?

        path = route.path.spec.to_s.sub(/\(\.:format\)$/, "")
        path = mount_point + path unless mount_point.empty? || mount_point == "/"

        next if config.ignored_paths.any? { |regex| regex.match?(path) }

        RouteInfo.new(verb, path, route.defaults[:controller], route.defaults[:action])
      end
    end

    # Finds where an engine is mounted in the main application.
    #
    # @param engine_class [Class] the engine class to find
    # @return [String] the mount path (e.g., "/api/v1") or empty string if mounted at root
    def self.find_engine_mount_point(engine_class)
      Rails.application.routes.routes.each do |route|
        app = route.app
        app = app.app if app.respond_to?(:app)

        if app.is_a?(Class) && app == engine_class
          path = route.path.spec.to_s
          path = path.gsub(/\(\.:format\)$/, "")
          path = path.gsub(/\/\*.*$/, "")
          return path
        end
      end

      ""
    end
  end
end
