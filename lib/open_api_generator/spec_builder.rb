# frozen_string_literal: true

module OpenApiGenerator
  # Builds an OpenAPI 3.0 specification from discovered routes and controller documentation.
  #
  # This class orchestrates the entire spec generation process:
  # 1. Discovers routes from the application and engines
  # 2. Filters routes based on controller settings
  # 3. Builds OpenAPI operations for each route
  # 4. Combines everything into a valid OpenAPI 3.0 spec
  class SpecBuilder
    # Builds the complete OpenAPI specification.
    #
    # @param config [Configuration] the configuration object
    # @return [Hash] a complete OpenAPI 3.0 specification
    def self.call(config:)
      routes = RouteDiscovery.call(config: config)
      registry = SchemaRegistry.new

      paths = {}
      routes.each do |route|
        controller_class = constantize_controller(route.controller)
        next unless controller_class
        next if config.ignored_controllers.include?(controller_class.name)
        next unless include_controller?(controller_class, config)
        next if ignore_action?(controller_class, route.action)

        oas_path = convert_path_to_open_api(route.path)
        verb = route.verb.downcase

        paths[oas_path] ||= {}
        paths[oas_path][verb] = build_operation(config, controller_class, route.action, oas_path, registry)
      end

      spec = {
        open_api: "3.0.3",
        info: build_info(config),
        servers: config.servers,
        paths: paths,
        components: { schemas: registry.to_h }
      }
      spec[:components][:securitySchemes] = config.security_schemes if config.security_schemes.present?
      spec[:security] = config.security if config.security.present?
      spec
    end

    def self.route_introspection(config:)
      routes = RouteDiscovery.call(config: config)
      build_route_introspection(routes, config)
    end

    # Returns the discovered operations and whether each write operation has a
    # request body declaration. This is intentionally separate from the final
    # OpenAPI document so completeness checks can run without duplicating route
    # filtering logic.
    def self.discover_operations(config)
      RouteDiscovery.call(config: config).filter_map do |route|
        controller_class = constantize_controller(route.controller)
        next unless controller_class
        next if config.ignored_controllers.include?(controller_class.name)
        next unless include_controller?(controller_class, config)
        next if ignore_action?(controller_class, route.action)

        docs = get_action_docs(controller_class, route.action)
        {
          controller: controller_class.name,
          action: route.action,
          verb: route.verb,
          path: convert_path_to_open_api(route.path),
          has_request_body: request_body_declared?(controller_class, route.action, docs)
        }
      end
    end

    # Converts a controller path string to a controller class.
    #
    # @param controller_path [String] the controller path (e.g., "api/users")
    # @return [Class, nil] the controller class or nil if not found
    # @example
    #   constantize_controller("api/users") # => Api::UsersController
    def self.constantize_controller(controller_path)
      "#{controller_path}_controller".camelize.safe_constantize
    end

    # Determines if a controller should be included in the spec.
    #
    # @param controller_class [Class] the controller class
    # @return [Boolean] true if the controller should be included
    def self.include_controller?(controller_class, config)
      return false unless controller_class.respond_to?(:open_api_generator_json_mode)

      mode = controller_class.open_api_generator_json_mode
      return true if mode == :json
      return false if mode == :ignore

      included_by_ancestor?(controller_class, config) || controller_class < ActionController::API
    end

    def self.included_by_ancestor?(controller_class, config)
      bases = config.included_base_controllers
      return false if bases.blank?

      controller_class.ancestors.any? do |ancestor|
        ancestor.is_a?(Class) && bases.include?(ancestor.name)
      end
    end

    # Determines if an action should be excluded from the spec.
    #
    # @param controller_class [Class] the controller class
    # @param action [String] the action name
    # @return [Boolean] true if the action should be excluded
    def self.ignore_action?(controller_class, action)
      return false unless controller_class.respond_to?(:open_api_generator_ignored_actions)

      controller_class.open_api_generator_ignored_actions.include?(action.to_s)
    end

    # Builds the info section of the OpenAPI spec.
    #
    # @param config [Configuration] the configuration object
    # @return [Hash] the info object
    def self.build_info(config)
      info = {
        title: config.title,
        version: config.version
      }
      info[:description] = config.description if config.description
      info
    end

    # Builds an OpenAPI operation object for a route.
    #
    # @param config [Configuration] the configuration object
    # @param controller_class [Class] the controller class
    # @param action [String] the action name
    # @param oas_path [String] the OpenAPI-formatted path
    # @return [Hash] an OpenAPI operation object
    def self.build_operation(config, controller_class, action, oas_path, registry = SchemaRegistry.new)
      docs = get_action_docs(controller_class, action)

      operation = {
        tags: build_tags(controller_class, docs),
        operationId: docs[:operation_id] || "#{controller_class.name}##{action}",
        parameters: build_parameters(oas_path, docs),
        responses: ResponseBuilder.build(config, controller_class, action, docs, registry)
      }

      operation[:summary] = docs[:summary] if docs[:summary]
      operation[:description] = docs[:description] if docs[:description]
      request_body = RequestBodyBuilder.build(controller_class, action, docs, registry)
      operation[:requestBody] = request_body if request_body
      operation[:security] = docs[:security] if docs.key?(:security)
      operation["x-tool-name"] = docs[:tool_name] if docs[:tool_name]
      docs[:extensions]&.each do |key, value|
        extension = key.to_s.start_with?("x-") ? key.to_s : "x-#{key}"
        operation[extension] = value
      end

      operation
    end

    def self.build_route_introspection(routes, config)
      routes.filter_map do |route|
        controller_class = constantize_controller(route.controller)
        next unless controller_class
        next if config.ignored_controllers.include?(controller_class.name)
        next unless include_controller?(controller_class, config)
        next if ignore_action?(controller_class, route.action)

        oas_path = convert_path_to_open_api(route.path)
        docs = get_action_docs(controller_class, route.action)
        params = summarize_parameters(oas_path, docs)

        {
          controller: controller_class.name,
          action: route.action,
          verb: route.verb,
          rails_path: route.path,
          open_api_path: oas_path,
          required_parameters: params[:required],
          optional_parameters: params[:optional]
        }
      end
    end

    def self.summarize_parameters(oas_path, docs)
      summary = { required: [], optional: [] }

      build_parameters(oas_path, docs).each do |param|
        name = parameter_field(param, :name)
        location = parameter_field(param, :in) || "query"
        next unless name

        entry = { name: name, in: location }
        bucket = parameter_required?(param) ? :required : :optional
        summary[bucket] << entry
      end

      summary
    end

    def self.parameter_required?(param)
      required = parameter_field(param, :required)
      return normalize_boolean(required) unless required.nil?

      parameter_field(param, :in) == "path"
    end

    def self.normalize_boolean(value)
      return value if value == true || value == false

      if value.respond_to?(:to_s)
        string = value.to_s.strip
        return true if string.casecmp("true").zero? || string == "1"
        return false if string.casecmp("false").zero? || string == "0"
      end

      !!value
    end

    def self.parameter_field(param, key)
      return unless param.respond_to?(:key?)

      sym_key = key.to_sym
      str_key = key.to_s

      return param[sym_key] if param.key?(sym_key)
      return param[str_key] if param.key?(str_key)

      nil
    end

    # Retrieves documentation for a specific action.
    #
    # @param controller_class [Class] the controller class
    # @param action [String] the action name
    # @return [Hash] the documentation hash or empty hash if none exists
    def self.get_action_docs(controller_class, action)
      return {} unless controller_class.respond_to?(:open_api_generator_action_docs)

      controller_class.open_api_generator_action_docs.fetch(action.to_s, {})
    end

    def self.request_body_declared?(controller_class, action, docs)
      return true if docs.key?(:requestBody) && !docs[:requestBody].nil?

      RequestBodyBuilder.input_spec(controller_class, action).present?
    end

    # Builds the tags array for an operation.
    #
    # @param controller_class [Class] the controller class
    # @param docs [Hash] the action documentation
    # @return [Array<String>] array of tag names
    def self.build_tags(controller_class, docs)
      return docs[:tags] if docs[:tags]

      if controller_class.respond_to?(:open_api_generator_tag) && controller_class.open_api_generator_tag
        return [controller_class.open_api_generator_tag]
      end

      [generate_tag_from_controller(controller_class)]
    end

    # Generates a tag name from a controller class name.
    #
    # @param controller_class [Class] the controller class
    # @return [String] the generated tag name
    # @example
    #   generate_tag_from_controller(Api::UsersController) # => "Api Users"
    def self.generate_tag_from_controller(controller_class)
      controller_class.name
        .sub(/Controller$/, "")
        .underscore
        .tr("/", " ")
        .titleize
    end

    # Builds the parameters array for an operation.
    #
    # Combines path parameters extracted from the route with any
    # explicitly documented parameters.
    #
    # @param oas_path [String] the OpenAPI-formatted path
    # @param docs [Hash] the action documentation
    # @return [Array<Hash>] array of parameter objects
    def self.build_parameters(oas_path, docs)
      path_params = extract_path_parameters(oas_path)
      explicit_params = docs[:parameters] || []

      merge_parameters(path_params, explicit_params)
    end

    # Extracts path parameters from an OpenAPI path string.
    #
    # @param oas_path [String] the OpenAPI path (e.g., "/users/{id}")
    # @return [Array<Hash>] array of path parameter objects
    def self.extract_path_parameters(oas_path)
      oas_path.scan(/\{(\w+)\}/).flatten.map do |param_name|
        {
          name: param_name,
          in: "path",
          required: true,
          schema: { type: "string" }
        }
      end
    end

    # Merges path parameters with explicit parameters, avoiding duplicates.
    #
    # @param path_params [Array<Hash>] path parameters
    # @param explicit_params [Array<Hash>] explicitly documented parameters
    # @return [Array<Hash>] merged array of parameters
    def self.merge_parameters(path_params, explicit_params)
      all_params = path_params + explicit_params
      seen = {}

      all_params.select do |param|
        name = parameter_field(param, :name)
        location = parameter_field(param, :in)
        key = "#{location}:#{name}"

        next false if seen[key]
        seen[key] = true
        true
      end
    end

    # Builds the responses object for an operation.
    #
    # @param config [Configuration] the configuration object
    # @param docs [Hash] the action documentation
    # @return [Hash] hash of response objects keyed by status code
    def self.build_responses(config, docs)
      return docs[:responses] if docs[:responses]

      {
        "200" => {
          description: config.default_response_description
        }
      }
    end

    # Converts a Rails path pattern to OpenAPI format.
    #
    # @param rails_path [String] the Rails path (e.g., "/users/:id")
    # @return [String] the OpenAPI path (e.g., "/users/{id}")
    def self.convert_path_to_open_api(rails_path)
      rails_path.gsub(/:([a-zA-Z_]\w*)/, '{\1}')
    end
  end
end
