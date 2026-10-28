require "test_helper"
require "minitest/mock"

module RouteEligibility
  class ExplicitController < ActionController::Base
    include OpenApiGenerator::ControllerDSL
    swagger_json!
    swagger :show, operation_id: "explicit_fixture", security: []
    api_path_param :id, :integer
  end

  class ConfiguredBaseController < ActionController::Base
    include OpenApiGenerator::ControllerDSL
  end

  class InheritedController < ConfiguredBaseController; end

  class ApiController < ActionController::API
    include OpenApiGenerator::ControllerDSL
  end

  class PlainController < ActionController::Base
    include OpenApiGenerator::ControllerDSL
  end

  class WithoutDslController < ActionController::API; end
  class IgnoredController < ExplicitController; end

  class HiddenController < ExplicitController
    swagger_ignore!
  end

  class ExcludedActionController < ExplicitController
    swagger_ignore_action :create
  end
end

class RouteEligibilityTest < ActiveSupport::TestCase
  setup do
    @config = OpenApiGenerator::Configuration.new
    @config.included_base_controllers = [ "RouteEligibility::ConfiguredBaseController" ]
    @config.ignored_controllers = [ "RouteEligibility::IgnoredController" ]
    @config.default_response_description = "Fallback response"
    @routes = [
      route("explicit", "show", "/mount/:orgslug/widgets/:id", "GET"),
      route("inherited", "index"),
      route("api", "index"),
      route("plain", "index"),
      route("without_dsl", "index"),
      route("missing", "index"),
      route("ignored", "create", "/ignored", "POST"),
      route("hidden", "create", "/hidden", "POST"),
      route("excluded_action", "create", "/excluded", "POST")
    ]
  end

  test "spec, introspection and discovery apply the same route eligibility matrix" do
    spec, introspection, discovered = outputs
    expected = [ "/mount/{orgslug}/widgets/{id}", "/inherited", "/api" ]

    assert_equal expected, spec[:paths].keys
    assert_equal expected, introspection.map { |entry| entry[:open_api_path] }
    assert_equal expected, discovered.map { |entry| entry[:path] }
    operation = spec[:paths].fetch(expected.first).fetch("get")
    assert_equal "explicit_fixture", operation[:operationId]
    assert_equal [], operation[:security]
    id = operation[:parameters].find { |parameter| parameter[:name] == "id" }
    assert_equal({ type: "integer" }, id[:schema])
    assert_equal "/mount/:orgslug/widgets/:id", introspection.first[:rails_path]
    assert_equal [ "orgslug", "id" ], introspection.first[:required_parameters].map { |parameter| parameter[:name] }
    assert_equal({ "200" => { description: "Fallback response" } }, spec[:paths].fetch("/inherited").fetch("get")[:responses])
  end

  test "auditing ignored JSON mode includes hidden writes without exposing excluded controllers or actions" do
    OpenApiGenerator::RouteDiscovery.stub(:call, @routes) do
      audited = OpenApiGenerator::Completeness.audit(config: @config, include_ignored: true)
      assert_equal [ "/hidden" ], audited.map(&:path)
      assert_empty OpenApiGenerator::Completeness.audit(config: @config)
      spec, introspection, discovered = outputs
      refute spec[:paths].key?("/hidden")
      refute_includes introspection.map { |entry| entry[:open_api_path] }, "/hidden"
      refute_includes discovered.map { |entry| entry[:path] }, "/hidden"
    end
  end

  test "eligibility resolves current configuration on each call" do
    assert_equal 3, outputs.first[:paths].length
    @config.ignored_controllers << "RouteEligibility::ExplicitController"
    spec, introspection, discovered = outputs
    refute spec[:paths].key?("/mount/{orgslug}/widgets/{id}")
    assert_equal 2, introspection.length
    assert_equal 2, discovered.length
  end

  private

  def route(controller, action, path = "/#{controller}", verb = "GET")
    OpenApiGenerator::RouteDiscovery::RouteInfo.new(verb, path, "route_eligibility/#{controller}", action)
  end

  def outputs
    OpenApiGenerator::RouteDiscovery.stub(:call, @routes) do
      [
        OpenApiGenerator::SpecBuilder.call(config: @config),
        OpenApiGenerator::SpecBuilder.route_introspection(config: @config),
        OpenApiGenerator::SpecBuilder.discover_operations(@config)
      ]
    end
  end
end
