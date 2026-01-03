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
      base.class_attribute :open_api_generator_json_mode, default: :auto
      base.class_attribute :open_api_generator_tag, default: nil
      base.class_attribute :open_api_generator_action_docs, default: {}
      base.class_attribute :open_api_generator_ignored_actions, default: Set.new
    end

    # Class methods added to controllers when ControllerDSL is included.
    module ClassMethods
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
      def swagger(action_name, summary: nil, description: nil, tags: nil, parameters: nil, request_body: nil, responses: nil)
        action = action_name.to_s
        doc = {
          summary: summary,
          description: description,
          tags: tags,
          parameters: parameters || [],
          requestBody: request_body,
          responses: responses
        }.compact

        self.open_api_generator_action_docs = open_api_generator_action_docs.merge(action => doc)
      end
    end
  end
end
