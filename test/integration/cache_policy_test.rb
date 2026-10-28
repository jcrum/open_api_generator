require "test_helper"
require "minitest/mock"

class CachePolicyTest < ActionDispatch::IntegrationTest
  class RecordingStore < ActiveSupport::Cache::MemoryStore
    attr_reader :fetches

    def initialize
      super
      @fetches = []
    end

    def fetch(key, **options, &block)
      @fetches << [ key, options ]
      super
    end
  end

  setup do
    OpenApiGenerator.instance_variable_set(:@config, nil)
    @config = OpenApiGenerator.config
    @config.cache_enabled = true
    @config.cache_key = "host/custom-spec"
    @config.cache_ttl = 2.minutes
    @store = RecordingStore.new
    @builds = { spec: 0, routes: 0 }
  end

  teardown do
    OpenApiGenerator.instance_variable_set(:@config, nil)
  end

  test "JSON and YAML share a spec cache while introspection uses its own key and common policy" do
    with_builders do
      get "/doc/spec.json"
      assert_response :success
      assert_equal "3.0.3", JSON.parse(response.body)["openapi"]
      get "/doc/spec.yaml"
      assert_response :success
      assert_equal({ openapi: "3.0.3", paths: {} }.to_yaml, response.body)
      Rails.env.stub(:development?, true) do
        2.times { get "/doc/routes.json" }
      end
      assert_response :success
      assert_equal [ { "path" => "/widgets" } ], JSON.parse(response.body)
    end

    assert_equal({ spec: 1, routes: 1 }, @builds)
    assert_equal [ "host/custom-spec", "host/custom-spec", "host/custom-spec/routes", "host/custom-spec/routes" ], @store.fetches.map(&:first)
    @store.fetches.each do |_key, options|
      assert_equal 2.minutes, options[:expires_in]
      assert_equal 30.seconds, options[:race_condition_ttl]
    end
  end

  test "disabled caching builds every response and never reads the cache" do
    @config.cache_enabled = false
    @config.stub(:cache_key, -> { raise "disabled caching must not fingerprint routes" }) do
      with_builders do
        2.times { get "/doc/spec.json" }
        Rails.env.stub(:development?, true) do
          2.times { get "/doc/routes.json" }
        end
      end
    end

    assert_equal({ spec: 2, routes: 2 }, @builds)
    assert_empty @store.fetches
  end

  test "a cached document never bypasses authorization" do
    @config.authorize = ->(_controller) { true }
    with_builders do
      get "/doc/spec.json"
      assert_response :success
      @config.authorize = ->(_controller) { false }
      Rails.env.stub(:development?, true) do
        %w[/doc/spec.json /doc/spec.yaml /doc/routes.json].each do |path|
          get path
          assert_response :not_found
          assert_empty response.body
        end
      end
    end

    assert_equal({ spec: 1, routes: 0 }, @builds)
    assert_equal 1, @store.fetches.length
  end

  test "introspection remains unavailable outside development before any cache read or build" do
    with_builders do
      Rails.env.stub(:development?, false) { get "/doc/routes.json" }
      assert_response :not_found
    end

    assert_equal({ spec: 0, routes: 0 }, @builds)
    assert_empty @store.fetches
  end

  private

  def with_builders(&block)
    spec_builder = lambda do |config:|
      assert_same @config, config
      @builds[:spec] += 1
      { openapi: "3.0.3", paths: {} }
    end
    route_builder = lambda do |config:|
      assert_same @config, config
      @builds[:routes] += 1
      [ { path: "/widgets" } ]
    end
    Rails.stub(:cache, @store) do
      OpenApiGenerator::SpecBuilder.stub(:call, spec_builder) do
        OpenApiGenerator::SpecBuilder.stub(:route_introspection, route_builder, &block)
      end
    end
  end
end
