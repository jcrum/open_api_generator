require "test_helper"
require "minitest/mock"

class AuthorizationTest < ActionDispatch::IntegrationTest
  ENDPOINTS = %w[/doc/spec.json /doc/spec.yaml /doc/routes.json].freeze

  setup do
    Rails.cache.clear
    OpenApiGenerator.instance_variable_set(:@config, nil)
    OpenApiGenerator.configure do |cfg|
      cfg.cache_enabled = false
      cfg.ignored_paths = [%r{^/rails}]
    end
  end

  teardown do
    OpenApiGenerator.instance_variable_set(:@config, nil)
  end

  test "without an authorizer the docs are public" do
    get "/doc/spec.json"
    assert_response :success

    get "/doc/spec.yaml"
    assert_response :success
  end

  test "a falsy authorizer answers an empty 404 for every format" do
    OpenApiGenerator.config.authorize = ->(_controller) { false }

    ENDPOINTS.each do |path|
      get path
      assert_response :not_found, path
      assert_empty response.body, path
    end
  end

  test "a nil authorizer result is denied" do
    OpenApiGenerator.config.authorize = ->(_controller) { nil }

    get "/doc/spec.json"
    assert_response :not_found
  end

  test "a truthy authorizer serves the docs" do
    OpenApiGenerator.config.authorize = ->(_controller) { true }

    get "/doc/spec.json"
    assert_response :success
    assert_equal "3.0.3", JSON.parse(response.body)["openapi"]

    get "/doc/spec.yaml"
    assert_response :success

    Rails.env.stub(:development?, true) do
      get "/doc/routes.json"
    end
    assert_response :success
  end

  test "the authorizer receives the controller and runs before the cache read and the build" do
    received = nil
    OpenApiGenerator.config.authorize = lambda do |controller|
      received = controller
      false
    end
    OpenApiGenerator.config.cache_enabled = true

    explode = ->(*) { raise "build must not run" }
    store = ActiveSupport::Cache::MemoryStore.new
    Rails.stub(:cache, store) do
      OpenApiGenerator::SpecBuilder.stub(:call, explode) do
        ENDPOINTS.each { |path| get path }
      end
    end

    assert_response :not_found
    assert_kind_of OpenApiGenerator::OpenApiController, received
    assert_equal 0, store.instance_variable_get(:@data).size
  end
end
