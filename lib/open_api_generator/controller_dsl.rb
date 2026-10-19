# frozen_string_literal: true

require "set"

module OpenApiGenerator
  # DSL for documenting controllers and actions in OpenAPI format.
  #
  # Include this module in your controllers and use the class methods
  # to mark controllers for documentation and document individual actions.
  #
  # @example Basic usage
  #   class Api::UsersController < ActionController::API
  #     include OpenApiGenerator::ControllerDSL
  #     swagger_json!
  #     swagger_tag "Users"
  #
  #     swagger :create,
  #       summary: "Create a user",
  #       responses: { "201" => { description: "User created" } }
  #
  #     def create
  #       # ...
  #     end
  #   end
  module ControllerDSL
    def self.included(base)
      base.extend(ClassMethods)
      base.class_attribute :open_api_generator_json_mode, instance_accessor: false, default: :auto
      base.class_attribute :open_api_generator_tag, instance_accessor: false, default: nil
      base.class_attribute :open_api_generator_action_docs, instance_accessor: false, default: {}
      base.class_attribute :open_api_generator_ignored_actions, instance_accessor: false, default: Set.new
      base.class_attribute :open_api_generator_input_specs, instance_accessor: false, default: {}
      base.class_attribute :open_api_generator_response_specs, instance_accessor: false, default: {}
      # Typed path parameters, keyed `[name, within]` (see `api_path_param`).
      base.class_attribute :open_api_generator_path_params, instance_accessor: false, default: {}
      # Class-level default for `api_response envelope:`. nil and :none mean no envelope;
      # :data wraps bodies as `{ data: ..., meta: ... }`. Inherited; a subclass or a
      # single `api_response envelope:` overrides it.
      # Not redefined when an ancestor already included the DSL, so a host base class can set it.
      unless base.respond_to?(:open_api_generator_response_envelope)
        base.class_attribute :open_api_generator_response_envelope, instance_accessor: false, default: nil
      end

      # Private so it is never routable as an action.
      base.class_eval do
        private

        def permitted(action = action_name)
          spec = self.class.open_api_generator_input_specs[action.to_s]
          raise ArgumentError, "no api_params declared for #{self.class}##{action}" unless spec

          spec.permit(params, path_keys: request&.path_parameters&.keys || [])
        end
      end
    end

    # Class methods added to controllers when ControllerDSL is included.
    module ClassMethods
      ENVELOPES = %i[data none].freeze

      # Declares the response of an action.
      #
      # @param envelope [Symbol, nil] `:data` wraps the schema as `{ data: X }`, or
      #   `{ data: [X], meta: { type: object } }` when `collection: true`. `:none` leaves it
      #   bare. nil uses the class default (`open_api_generator_response_envelope`).
      def api_response(action, status: 200, serializer: nil, model: nil, collection: false, description: nil, envelope: nil)
        unless envelope.nil? || ENVELOPES.include?(envelope)
          raise ArgumentError, "envelope must be one of #{ENVELOPES.inspect}, got #{envelope.inspect}"
        end

        response = {
          status: status,
          serializer: serializer,
          model: model,
          collection: collection,
          description: description,
          envelope: envelope
        }
        self.open_api_generator_response_specs = open_api_generator_response_specs.merge(action.to_s => response)
      end

      def api_params(action, permit:, wrapped_in: nil, model: nil)
        spec = OpenApiGenerator::InputSpec.new(
          action: action,
          permit: permit,
          wrapped_in: wrapped_in,
          model: model
        )
        self.open_api_generator_input_specs = open_api_generator_input_specs.merge(action.to_s => spec)
      end

      PATH_PARAM_TYPES = %i[uuid string integer].freeze

      # Declares the schema of a path parameter (`{id}`, `{board_id}`) for every route of
      # this controller (and subclasses) that has a path param of that name. Undeclared path
      # params stay `{ type: string }`.
      #
      # @param type [Symbol] `:uuid` (the configured `scalar_overrides[:uuid]`, base36 ids in
      #   Paxfish hosts), `:string` or `:integer`; anything else raises
      # @param within [Symbol, Array<Symbol>] only routes whose path also has these params.
      #   Use it when one name means different things per route (`/cards/{id}` is a uuid,
      #   `/boards/{board_id}/cards/{id}` an integer number). The declaration with the most
      #   matching `within` params wins; two equally specific matches raise `ArgumentError`.
      # @param enum [Array, nil] allowed values
      # @param pattern [String, nil] regular expression for the value
      def api_path_param(name, type = :string, within: [], enum: nil, pattern: nil)
        type = type.respond_to?(:to_sym) ? type.to_sym : type
        unless PATH_PARAM_TYPES.include?(type)
          raise ArgumentError, "api_path_param type must be one of #{PATH_PARAM_TYPES.inspect}, got #{type.inspect}"
        end

        raise ArgumentError, "api_path_param enum must be an Array, got #{enum.inspect}" unless enum.nil? || enum.is_a?(Array)
        raise ArgumentError, "api_path_param pattern must be a String, got #{pattern.inspect}" unless pattern.nil? || pattern.is_a?(String)

        within = Array(within).map(&:to_s).sort.freeze
        entry = { type: type, enum: enum&.map(&:to_s)&.freeze, pattern: pattern }.freeze
        self.open_api_generator_path_params = open_api_generator_path_params.merge([ name.to_s, within ] => entry)
      end

      # Marks this controller to be included in the OpenAPI spec.
      #
      # By default, only ActionController::API controllers are included.
      # Call this method in ActionController::Base controllers to include them.
      #
      # @example
      #   class UsersController < ApplicationController
      #     include OpenApiGenerator::ControllerDSL
      #     swagger_json!
      #   end
      def swagger_json!
        self.open_api_generator_json_mode = :json
      end

      # Marks this controller to be excluded from the OpenAPI spec.
      #
      # @example
      #   class InternalController < ActionController::API
      #     include OpenApiGenerator::ControllerDSL
      #     swagger_ignore!
      #   end
      def swagger_ignore!
        self.open_api_generator_json_mode = :ignore
      end

      # Sets a tag for all actions in this controller.
      #
      # Tags are used to group operations in the OpenAPI spec.
      #
      # @param name [String] the tag name
      # @example
      #   class UsersController < ActionController::API
      #     include OpenApiGenerator::ControllerDSL
      #     swagger_json!
      #     swagger_tag "User Management"
      #   end
      def swagger_tag(name)
        self.open_api_generator_tag = name
      end

      # Excludes specific actions from the OpenAPI spec.
      #
      # @param actions [Array<Symbol>] the action names to exclude
      # @example
      #   class UsersController < ActionController::API
      #     include OpenApiGenerator::ControllerDSL
      #     swagger_json!
      #     swagger_ignore_action :internal_only, :debug
      #   end
      def swagger_ignore_action(*actions)
        self.open_api_generator_ignored_actions += actions.map(&:to_s)
      end

      # Documents an action with OpenAPI metadata.
      #
      # @param action_name [Symbol] the name of the action to document
      # @param summary [String, nil] brief description of the action
      # @param description [String, nil] detailed description of the action
      # @param tags [Array<String>, nil] tags for this action (overrides controller tag)
      # @param parameters [Array<Hash>, nil] array of parameter definitions
      # @param request_body [Hash, nil] request body schema
      # @param responses [Hash, nil] hash of response definitions
      #
      # @example Simple documentation
      #   swagger :index,
      #     summary: "List users",
      #     responses: {
      #       "200" => { description: "Success" }
      #     }
      #
      # @example With request body
      #   swagger :create,
      #     summary: "Create a user",
      #     request_body: {
      #       required: true,
      #       content: {
      #         "application/json" => {
      #           schema: {
      #             type: "object",
      #             properties: {
      #               name: { type: "string" },
      #               email: { type: "string" }
      #             }
      #           }
      #         }
      #       }
      #     },
      #     responses: {
      #       "201" => { description: "User created" }
      #     }
      # `tool_name:` tags the operation as an MCP tool (`x-tool-name`). Pass `true` to
      # use the generated operationId (for an action routed more than once).
      def swagger(action_name, summary: nil, description: nil, tags: nil, parameters: nil, request_body: nil, responses: nil, security: nil, operation_id: nil, tool_name: nil, extensions: nil)
        action = action_name.to_s
        doc = {
          summary: summary,
          description: description,
          tags: tags,
          parameters: parameters || [],
          requestBody: request_body,
          responses: responses,
          operation_id: operation_id,
          tool_name: tool_name,
          extensions: extensions
        }.compact
        doc[:security] = security unless security.nil?

        self.open_api_generator_action_docs = open_api_generator_action_docs.merge(action => doc)
      end
    end
  end
end
