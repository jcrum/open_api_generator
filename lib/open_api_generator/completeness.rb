# frozen_string_literal: true

module OpenApiGenerator
  # Audits write operations for a machine-readable request body declaration, and
  # that every documented operation is served by a route the host can reach.
  module Completeness
    Offense = Struct.new(:controller, :action, :verb, :path, keyword_init: true)
    WRITE = %w[POST PUT PATCH].freeze

    # @param include_ignored [Boolean] also audit controllers in `:ignore` mode
    #   (hidden from the spec, such as machine-only controllers) for request bodies
    def self.audit(config:, include_ignored: false)
      SpecBuilder.__send__(:discover_operations, config, include_ignored: include_ignored).filter_map do |operation|
        next unless WRITE.include?(operation[:verb].to_s.upcase)
        next if operation[:has_request_body]

        Offense.new(
          controller: operation[:controller],
          action: operation[:action],
          verb: operation[:verb],
          path: operation[:path]
        )
      end
    end

    # Lists routed path params named `id` or `*_id` (never `orgslug`) that no
    # `api_path_param` declaration (honoring `within:`) and no explicit swagger
    # `in: path` parameter types. Host tests assert it is empty so a new route cannot ship
    # an untyped identifier.
    #
    # @return [Array<String>] "VERB /path {name} (Controller#action)" strings
    def self.undeclared_path_params(config:, include_ignored: false)
      operations = SpecBuilder.__send__(:discover_operations, config, include_ignored: include_ignored)

      operations.flat_map do |operation|
        names = SpecBuilder.path_param_names(operation[:path])
        explicit = Array(operation[:docs][:parameters]).filter_map do |param|
          SpecBuilder.parameter_field(param, :name).to_s if SpecBuilder.parameter_field(param, :in).to_s == "path"
        end

        names.filter_map do |name|
          next unless name == "id" || name.end_with?("_id")
          next if explicit.include?(name)
          next if SpecBuilder.path_param_declared?(operation[:controller_class], name, operation[:path])

          "#{operation[:verb].to_s.upcase} #{operation[:path]} {#{name}} (#{operation[:controller]}##{operation[:action]})"
        end
      end.uniq
    end

    # Lists documented operations that the host routes do not serve as documented
    # (for example an engine documented without a mount point). Each documented
    # operation's path is filled with sample values and recognized against
    # `Rails.application.routes` (Rails descends into mounted engines). It counts as
    # reachable only when the recognized controller and action match the documented ones.
    #
    # Limits: recognition runs without a request, so route constraints that are lambdas
    # over the request (headers, host, subdomain) cannot be satisfied and are reported as
    # unreachable, and a path param needs a sample that satisfies its route constraint.
    #
    # @param samples [Hash{String=>String}] values for path parameters; others use "1"
    # @return [Array<String>] "VERB /path" strings
    def self.unreachable(config:, samples: {})
      operations = SpecBuilder.__send__(:discover_operations, config, include_ignored: false)

      operations.uniq { |op| [ op[:verb], op[:path], op[:controller], op[:action] ] }.filter_map do |operation|
        sample = operation[:path].gsub(/\{([^}]+)\}/) { samples.fetch(Regexp.last_match(1), "1") }
        recognized = begin
          Rails.application.routes.recognize_path(sample, method: operation[:verb].to_s.downcase.to_sym)
        rescue ActionController::RoutingError
          nil
        end
        served = recognized &&
          "#{recognized[:controller]}_controller".camelize == operation[:controller] &&
          recognized[:action] == operation[:action]
        "#{operation[:verb].to_s.upcase} #{operation[:path]}" unless served
      end
    end
  end
end
