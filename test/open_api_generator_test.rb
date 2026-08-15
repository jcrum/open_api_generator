require "test_helper"
require "minitest/mock"
require "rake"
require "tmpdir"

class OpenApiGeneratorTest < ActiveSupport::TestCase
  test "it has a version number" do
    assert OpenApiGenerator::VERSION
  end
end

class OpenApiGeneratorConfigurationTest < ActiveSupport::TestCase
  test "provides sensible defaults" do
    config = OpenApiGenerator::Configuration.new

    assert_equal "API", config.title
    assert_equal "1.0.0", config.version
    assert_nil config.description
    assert_equal [{ url: "/" }], config.servers
    assert_equal({}, config.security_schemes)
    assert_nil config.security
    assert_equal [], config.included_base_controllers
    assert config.cache_enabled
    assert_equal "open_api_generator/open_api", config.cache_key
    assert_equal 10.minutes, config.cache_ttl
    assert_equal "OK", config.default_response_description
  end
end

class OpenApiGeneratorControllerDSLTest < ActiveSupport::TestCase
  test "tracks controller level metadata" do
    controller = Class.new(ActionController::API)
    controller.include OpenApiGenerator::ControllerDSL

    controller.swagger_json!
    controller.swagger_tag "Samples"
    controller.swagger_ignore_action :secret
    controller.swagger :index, summary: "List items"

    assert_equal :json, controller.open_api_generator_json_mode
    assert_equal "Samples", controller.open_api_generator_tag
    assert_equal "List items", controller.open_api_generator_action_docs["index"][:summary]
    assert_includes controller.open_api_generator_ignored_actions, "secret"
  end

  test "preserves an explicit empty security requirement" do
    controller = Class.new(ActionController::API)
    controller.include OpenApiGenerator::ControllerDSL

    controller.swagger :login, security: []

    assert_equal [], controller.open_api_generator_action_docs["login"][:security]
  end
end

class OpenApiGeneratorRouteDiscoveryTest < ActiveSupport::TestCase
  Route = Struct.new(:defaults, :verb, :path)
  Path = Struct.new(:spec)
  PathSpec = Struct.new(:string) do
    def to_s
      string
    end
  end

  test "extracts routes and strips format segments" do
    config = OpenApiGenerator::Configuration.new
    route = Route.new({ controller: "api/widgets", action: "index" }, "GET$", Path.new(PathSpec.new("/api/widgets(.:format)")))

    results = OpenApiGenerator::RouteDiscovery.extract_routes([route], config)

    assert_equal 1, results.size
    info = results.first
    assert_equal "GET", info.verb
    assert_equal "/api/widgets", info.path
    assert_equal "api/widgets", info.controller
    assert_equal "index", info.action
  end

  test "honors ignored paths" do
    config = OpenApiGenerator::Configuration.new
    config.ignored_paths = [/^\/internal/]
    route = Route.new({ controller: "api/widgets", action: "index" }, "GET$", Path.new(PathSpec.new("/internal/widgets")))

    results = OpenApiGenerator::RouteDiscovery.extract_routes([route], config)

    assert_empty results
  end
end

class OpenApiGeneratorModelSchemaTest < ActiveSupport::TestCase
  Column = Struct.new(:type, :null)

  class DummyModel
    def self.columns_hash
      {
        "name" => Column.new(:string, false),
        "info" => Column.new(:json, true),
        "status" => Column.new(:integer, false)
      }
    end

    def self.defined_enums
      { "status" => { "draft" => 0, "published" => 1 } }
    end
  end

  test "builds schema with required and enum info" do
    schema = OpenApiGenerator::ModelSchema.schema_for(DummyModel)

    assert_equal "object", schema[:type]
    assert_equal %w[name status], schema[:required].sort
    assert_equal({ type: "string" }, schema[:properties]["name"])
    assert_equal({ type: "object" }, schema[:properties]["info"])
    assert_equal({ type: "string", enum: %w[draft published] }, schema[:properties]["status"])
  end

  test "supports writable, except, required, and array options" do
    model = Class.new(DummyModel) do
      def self.name
        "WritableModel"
      end

      def self.columns_hash
        super.merge(
          "id" => Column.new(:integer, false),
          "items_count" => Column.new(:integer, false),
          "updated_at" => Column.new(:datetime, false)
        )
      end
    end

    schema = OpenApiGenerator::ModelSchema.schema_for(
      model,
      writable: true,
      except: [:info],
      required: [:name],
      arrays: [:name]
    )

    assert_equal %w[name], schema[:required]
    assert_equal({ type: "array", items: { type: "string" } }, schema[:properties]["name"])
    refute schema[:properties].key?("id")
    refute schema[:properties].key?("items_count")
    refute schema[:properties].key?("updated_at")
    refute schema[:properties].key?("info")
  end
end

class OpenApiGeneratorInputSpecTest < ActiveSupport::TestCase
  test "parses required and array fields into params and schema" do
    spec = OpenApiGenerator::InputSpec.new(
      action: :create,
      permit: { title: :string!, tags: [:string] }
    )
    params = ActionController::Parameters.new(title: "Hello", tags: ["one"], ignored: "no")

    assert_equal({ title: "Hello", tags: ["one"] }, spec.permit(params))
    assert_equal({ type: "string" }, spec.schema[:properties]["title"])
    assert_equal({ type: "array", items: { type: "string" } }, spec.schema[:properties]["tags"])
    assert_equal ["title"], spec.schema[:required]
  end

  test "uses model enum values in input schemas" do
    spec = OpenApiGenerator::InputSpec.new(
      action: :create,
      model: OpenApiGeneratorModelSchemaTest::DummyModel,
      permit: { status: :string }
    )

    assert_equal %w[draft published], spec.schema[:properties]["status"][:enum]
  end
end

class OpenApiGeneratorSpecBuilderTest < ActiveSupport::TestCase
  test "builds spec for documented route" do
    route = OpenApiGenerator::RouteDiscovery::RouteInfo.new("GET", "/api/widgets/:id", "api/widgets", "show")
    config = OpenApiGenerator::Configuration.new
    config.title = "Dummy API"
    config.version = "2.0.0"
    config.ignored_paths = []
    config.ignored_controllers = []
    config.cache_enabled = false
    config.servers = [{ url: "/api" }]
    config.security_schemes = { bearerAuth: { type: "http", scheme: "bearer" } }
    config.security = [{ bearerAuth: [] }]

    spec = OpenApiGenerator::RouteDiscovery.stub(:call, [route]) do
      OpenApiGenerator::SpecBuilder.call(config: config)
    end

    operation = spec[:paths]["/api/widgets/{id}"]["get"]
    assert_equal "Dummy API", spec[:info][:title]
    assert_equal "2.0.0", spec[:info][:version]
    assert_equal [{ url: "/api" }], spec[:servers]
    assert_equal({ bearerAuth: { type: "http", scheme: "bearer" } }, spec[:components][:securitySchemes])
    assert_equal [{ bearerAuth: [] }], spec[:security]
    assert_equal "Fetch a widget", operation[:summary]
    assert_equal ["Widgets"], operation[:tags]
    assert_equal "Api::WidgetsController#show", operation[:operationId]
    assert_equal "id", operation[:parameters].first[:name]
  end

  test "includes descendants of configured base controllers" do
    route = OpenApiGenerator::RouteDiscovery::RouteInfo.new("GET", "/api/gadgets", "api/gadgets", "index")
    config = OpenApiGenerator::Configuration.new
    config.ignored_paths = []
    config.included_base_controllers = ["Api::AuthenticatedBaseController"]

    spec = OpenApiGenerator::RouteDiscovery.stub(:call, [route]) do
      OpenApiGenerator::SpecBuilder.call(config: config)
    end

    assert spec[:paths].key?("/api/gadgets")
  end

  test "emits an action security override" do
    route = OpenApiGenerator::RouteDiscovery::RouteInfo.new("GET", "/api/widgets", "api/widgets", "index")
    config = OpenApiGenerator::Configuration.new
    config.ignored_paths = []
    config.security = [{ bearerAuth: [] }]

    spec = OpenApiGenerator::RouteDiscovery.stub(:call, [route]) do
      OpenApiGenerator::SpecBuilder.call(config: config)
    end

    assert_equal [], spec[:paths]["/api/widgets"]["get"][:security]
  end

  test "builds response schemas and MCP operation metadata" do
    route = OpenApiGenerator::RouteDiscovery::RouteInfo.new("POST", "/api/gadgets", "api/gadgets", "create")
    config = OpenApiGenerator::Configuration.new
    config.ignored_paths = []
    config.included_base_controllers = ["Api::AuthenticatedBaseController"]

    spec = OpenApiGenerator::RouteDiscovery.stub(:call, [route]) do
      OpenApiGenerator::SpecBuilder.call(config: config)
    end

    operation = spec[:paths]["/api/gadgets"]["post"]
    assert_equal "create_gadget", operation[:operationId]
    assert_equal "add_gadget", operation["x-tool-name"]
    assert_equal true, operation["x-idempotent"]
    assert_equal "gadgets", operation["x-write_scope"]
    assert_equal({ "$ref" => "#/components/schemas/Gadget" }, operation[:responses]["201"][:content]["application/json"][:schema])
    gadget_schema = spec[:components][:schemas]["Gadget"]
    assert_equal "object", gadget_schema[:type]
    assert_equal({ type: "string" }, gadget_schema[:properties]["title"])
    assert_includes gadget_schema[:required], "title"
  end

  test "uses serializer schemas before model schemas" do
    serializer = Class.new do
      def self.name
        "GadgetSerializer"
      end

      def self.open_api_schema
        { type: "string", format: "uri" }
      end
    end
    controller = Class.new(ActionController::API)
    controller.include OpenApiGenerator::ControllerDSL
    controller.api_response :show, serializer: serializer
    registry = OpenApiGenerator::SchemaRegistry.new

    responses = OpenApiGenerator::ResponseBuilder.build(
      OpenApiGenerator::Configuration.new,
      controller,
      :show,
      {},
      registry
    )

    assert_equal({ "$ref" => "#/components/schemas/Gadget" }, responses["200"][:content]["application/json"][:schema])
    assert_equal({ type: "string", format: "uri" }, registry.to_h["Gadget"])
  end

  test "registers api_params schemas and request body references" do
    route = OpenApiGenerator::RouteDiscovery::RouteInfo.new("POST", "/api/gadgets", "api/gadgets", "create")
    config = OpenApiGenerator::Configuration.new
    config.ignored_paths = []
    config.included_base_controllers = ["Api::AuthenticatedBaseController"]

    spec = OpenApiGenerator::RouteDiscovery.stub(:call, [route]) do
      OpenApiGenerator::SpecBuilder.call(config: config)
    end

    request_body = spec[:paths]["/api/gadgets"]["post"][:requestBody]
    assert_equal({ "$ref" => "#/components/schemas/GadgetCreateRequest" }, request_body[:content]["application/json"][:schema])
    assert_equal true, request_body[:required]
    assert_equal({ type: "array", items: { type: "string" } }, spec[:components][:schemas]["GadgetCreateRequest"][:properties]["label_ids"])
  end

  test "permitted filters wrapped input params" do
    controller = Api::GadgetsController.new
    controller.params = ActionController::Parameters.new(
      gadget: { title: "Hello", description: "Details", label_ids: ["a"], ignored: "no" },
      ignored: "no"
    )

    assert_equal(
      { title: "Hello", description: "Details", label_ids: ["a"] },
      controller.permitted(:create)
    )
  end

  test "returns controller metadata for route introspection" do
    route = OpenApiGenerator::RouteDiscovery::RouteInfo.new("GET", "/api/widgets/:id", "api/widgets", "show")
    config = OpenApiGenerator::Configuration.new
    config.ignored_paths = []
    config.ignored_controllers = []

    entries = OpenApiGenerator::RouteDiscovery.stub(:call, [route]) do
      OpenApiGenerator::SpecBuilder.route_introspection(config: config)
    end

    assert_equal 1, entries.size
    entry = entries.first
    assert_equal "Api::WidgetsController", entry[:controller]
    assert_equal "show", entry[:action]
    assert_equal "GET", entry[:verb]
    assert_equal "/api/widgets/:id", entry[:rails_path]
    assert_equal "/api/widgets/{id}", entry[:open_api_path]
    assert_equal [{ name: "id", in: "path" }], entry[:required_parameters]
    assert_empty entry[:optional_parameters]
  end
end

class OpenApiGeneratorRakeTaskTest < ActiveSupport::TestCase
  setup do
    @rake = Rake::Application.new
    Rake.application = @rake
    @rake.define_task(Rake::Task, :environment) {}
    load File.expand_path("../lib/tasks/open_api_generator_tasks.rake", __dir__)
  end

  teardown do
    Rake.application = nil
  end

  test "writes spec to default path" do
    ENV.delete("OUTPUT")
    Dir.mktmpdir do |dir|
      output = File.join(dir, "openapi.json")

      Rails.stub(:root, Pathname.new(dir)) do
        OpenApiGenerator::SpecBuilder.stub(:call, { "info" => { "title" => "Stub" } }) do
          invoke_generate_task
        end
      end

      assert File.exist?(output)
      data = JSON.parse(File.read(output))
      assert_equal "Stub", data.dig("info", "title")
    end
  end

  test "honors OUTPUT environment variable" do
    Dir.mktmpdir do |dir|
      output = File.join(dir, "docs", "spec.json")
      ENV["OUTPUT"] = output

      begin
        OpenApiGenerator::SpecBuilder.stub(:call, { "paths" => {} }) do
          invoke_generate_task
        end
      ensure
        ENV.delete("OUTPUT")
      end

      assert File.exist?(output)
      data = JSON.parse(File.read(output))
      assert_equal({}, data["paths"])
    end
  end

  private

  def invoke_generate_task
    task = @rake["open_api_generator:generate"]
    task.reenable
    task.invoke
  end
end
