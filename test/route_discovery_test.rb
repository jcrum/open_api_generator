require "test_helper"
require "minitest/mock"

class RouteDiscoveryTest < ActiveSupport::TestCase
  class UnmountedEngine < Rails::Engine; end
  class PrefixedEngine < Rails::Engine; end
  class RootEngine < Rails::Engine; end

  ENGINES = [ UnmountedEngine, PrefixedEngine, RootEngine ].freeze

  setup do
    ENGINES.each do |engine|
      engine.routes.clear!
      engine.routes.draw { get "/things", to: "api/widgets#index" }
    end
  end

  teardown do
    ENGINES.each { |engine| engine.routes.clear! }
  end

  test "an engine with no mount point is not documented" do
    paths = discovered_paths { mount PrefixedEngine => "/prefixed", as: :prefixed_engine }

    assert_not_includes paths, "/things", "an unmounted engine must not be drawn as root"
    assert_includes paths, "/prefixed/things"
    assert_nil OpenApiGenerator::RouteDiscovery.find_engine_mount_point(UnmountedEngine)
  end

  test "a mounted engine keeps its mount prefix" do
    paths = discovered_paths { mount PrefixedEngine => "/prefixed", as: :prefixed_engine }

    assert_equal [ "/prefixed/things" ], paths
  end

  test "an engine mounted at root keeps root paths" do
    paths = discovered_paths { mount RootEngine => "/", as: :root_engine }

    assert_equal [ "/things" ], paths
  end

  test "an engine mounted inside a path scope keeps the scoped prefix" do
    paths = discovered_paths { scope("/:orgslug") { mount PrefixedEngine => "/inner", as: :scoped_engine } }

    assert_equal [ "/:orgslug/inner/things" ], paths
  end

  test "an engine mounted inside a constraints block keeps its prefix" do
    paths = discovered_paths do
      constraints(->(_request) { true }) { mount PrefixedEngine => "/guarded", as: :guarded_engine }
    end

    assert_equal [ "/guarded/things" ], paths
  end

  test "the dummy app documents only reachable operations" do
    assert_empty OpenApiGenerator::Completeness.unreachable(config: OpenApiGenerator.config)
  end

  test "unreachable flags a missing route and a route served by a different controller" do
    operations = [
      { verb: "GET", path: "/api/widgets", controller: "Api::WidgetsController", action: "index" },
      { verb: "GET", path: "/api/widgets", controller: "Api::GadgetsController", action: "index" },
      { verb: "GET", path: "/api/widgets/{id}", controller: "Api::WidgetsController", action: "index" },
      { verb: "GET", path: "/api/nothing", controller: "Api::WidgetsController", action: "index" },
      { verb: "DELETE", path: "/api/widgets/{id}", controller: "Api::WidgetsController", action: "destroy" }
    ]

    flagged = OpenApiGenerator::SpecBuilder.stub(:discover_operations, operations) do
      OpenApiGenerator::Completeness.unreachable(config: OpenApiGenerator.config)
    end

    assert_equal [ "GET /api/widgets", "GET /api/widgets/{id}", "GET /api/nothing", "DELETE /api/widgets/{id}" ], flagged
  end

  private

  # Discovers routes against a fake host app whose routes are the given mounts.
  def discovered_paths(&mounts)
    host_routes = ActionDispatch::Routing::RouteSet.new
    host_routes.draw(&mounts)
    fake_app = Struct.new(:routes).new(host_routes)
    engines = ENGINES + [ OpenApiGenerator::Engine ]

    Rails.stub(:application, fake_app) do
      Rails::Engine.stub(:subclasses, engines) do
        OpenApiGenerator::RouteDiscovery.call(config: OpenApiGenerator::Configuration.new).map(&:path)
      end
    end
  end
end
