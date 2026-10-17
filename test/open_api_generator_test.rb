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
    assert_nil config.authorize
    assert config.cache_key.start_with?("open_api_generator/open_api/")
    assert_equal 10.minutes, config.cache_ttl
    assert_equal "OK", config.default_response_description
  end
end

module Api
  class HiddenThingsController < ActionController::API
    include OpenApiGenerator::ControllerDSL
    swagger_ignore!

    def create; end
  end
end

class OpenApiGeneratorAuthorizeSetterTest < ActiveSupport::TestCase
  test "accepts nil and callables and rejects anything else" do
    config = OpenApiGenerator::Configuration.new
    config.authorize = ->(_controller) { true }
    config.authorize = nil
    assert_nil config.authorize

    assert_raises(ArgumentError) { config.authorize = true }
    assert_raises(ArgumentError) { config.authorize = "yes" }
  end
end

class OpenApiGeneratorCacheKeyTest < ActiveSupport::TestCase
  test "a host override is used verbatim" do
    config = OpenApiGenerator::Configuration.new
    config.cache_key = "custom/key"

    assert_equal "custom/key", config.cache_key
  end

  test "the default key follows the release when set" do
    config = OpenApiGenerator::Configuration.new
    keys = %w[r1 r2 r1].map do |release|
      Rails.application.config.x.stub(:release, release) { config.cache_key }
    end

    assert_equal keys[0], keys[2]
    refute_equal keys[0], keys[1]
    assert_match(%r{\Aopen_api_generator/open_api/\h{16}\z}, keys[0])
  end

  test "the default key falls back to a digest of the route set" do
    config = OpenApiGenerator::Configuration.new
    config.ignored_paths = []
    route = ->(path) { [OpenApiGenerator::RouteDiscovery::RouteInfo.new("GET", path, "api/widgets", "index")] }

    first = OpenApiGenerator::RouteDiscovery.stub(:call, route.call("/api/a")) { config.cache_key }
    config.instance_variable_set(:@route_digest, nil)
    second = OpenApiGenerator::RouteDiscovery.stub(:call, route.call("/api/b")) { config.cache_key }

    refute_equal first, second
  end

  test "different discriminators use separate cache entries and a raising build re-raises" do
    store = ActiveSupport::Cache::MemoryStore.new
    config = OpenApiGenerator.config
    original_cache_enabled = config.cache_enabled
    config.cache_enabled = true
    builds = 0
    builder = ->(**) { { "build" => builds += 1 } }

    begin
      Rails.stub(:cache, store) do
        OpenApiGenerator::SpecBuilder.stub(:call, builder) do
          first = Rails.application.config.x.stub(:release, "r1") { OpenApiGenerator::OpenApiController.new.send(:spec) }
          again = Rails.application.config.x.stub(:release, "r1") { OpenApiGenerator::OpenApiController.new.send(:spec) }
          other = Rails.application.config.x.stub(:release, "r2") { OpenApiGenerator::OpenApiController.new.send(:spec) }

          assert_equal first, again
          refute_equal first, other
        end

        failing = ->(**) { raise "boom" }
        OpenApiGenerator::SpecBuilder.stub(:call, failing) do
          Rails.application.config.x.stub(:release, "r3") do
            assert_raises(RuntimeError) { OpenApiGenerator::OpenApiController.new.send(:spec) }
          end
        end
      end
    ensure
      config.cache_enabled = original_cache_enabled
    end
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

  test "tool_name tags the operation, and true reuses the operationId for each route" do
    stub_const = Class.new(ActionController::API)
    stub_const.include OpenApiGenerator::ControllerDSL
    Object.const_set(:ToolTaggedWidgetsController, stub_const)
    stub_const.swagger :show, tool_name: "fetch_widget"
    stub_const.swagger :update, tool_name: true
    config = OpenApiGenerator.config

    named = OpenApiGenerator::SpecBuilder.build_operation(config, stub_const, "show", "/api/v1/tool_tagged_widgets/{id}", OpenApiGenerator::SchemaRegistry.new, "get")
    by_context = OpenApiGenerator::SpecBuilder.build_operation(config, stub_const, "update", "/api/v1/boards/{board_id}/tool_tagged_widgets/{id}", OpenApiGenerator::SchemaRegistry.new, "patch")
    plain = OpenApiGenerator::SpecBuilder.build_operation(config, stub_const, "update", "/api/v1/tool_tagged_widgets/{id}", OpenApiGenerator::SchemaRegistry.new, "patch")

    assert_equal "fetch_widget", named["x-tool-name"]
    assert_equal "update_tool_tagged_widget_by_board", by_context["x-tool-name"]
    assert_equal "update_tool_tagged_widget", plain["x-tool-name"]
  ensure
    Object.send(:remove_const, :ToolTaggedWidgetsController) if Object.const_defined?(:ToolTaggedWidgetsController)
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

  test "raises parameter missing when the wrapper key is not an object" do
    spec = OpenApiGenerator::InputSpec.new(action: :create, wrapped_in: :user, permit: { name: :string })

    ["foo", ["foo"]].each do |value|
      params = ActionController::Parameters.new(user: value)

      error = assert_raises(ActionController::ParameterMissing) { spec.permit(params) }

      assert_equal :user, error.param
    end
  end

  test "falls back to top-level params when the wrapper key is absent" do
    spec = OpenApiGenerator::InputSpec.new(action: :create, wrapped_in: :user, permit: { name: :string })
    params = ActionController::Parameters.new(name: "Ann", ignored: "no")

    assert_equal({ name: "Ann" }, spec.permit(params))
  end

  test "uses model enum values in input schemas" do
    spec = OpenApiGenerator::InputSpec.new(
      action: :create,
      model: OpenApiGeneratorModelSchemaTest::DummyModel,
      permit: { status: :string }
    )

    assert_equal %w[draft published], spec.schema[:properties]["status"][:enum]
  end

  test "permits and documents nested objects and arrays of objects" do
    spec = OpenApiGenerator::InputSpec.new(
      action: :create,
      permit: {
        detail: { note: :string, purposes: [:string] },
        targets: [[ target_id: :uuid!, role: :string ]]
      }
    )
    params = ActionController::Parameters.new(
      detail: { note: "note", purposes: ["food"], ignored: "no" },
      targets: [{ target_id: "1", role: "subject", ignored: "no" }]
    )

    assert_equal(
      { detail: { note: "note", purposes: ["food"] }, targets: [{ target_id: "1", role: "subject" }] },
      spec.permit(params)
    )
    assert_equal "object", spec.schema[:properties]["detail"][:type]
    assert_equal "array", spec.schema[:properties]["targets"][:type]
    assert_equal "object", spec.schema[:properties]["targets"][:items][:type]
  end
end

class OpenApiGeneratorRequiredSchemaTest < ActiveSupport::TestCase
  test "emits required for scalar, nested and array-of-object fields" do
    spec = OpenApiGenerator::InputSpec.new(
      action: :create,
      permit: {
        title: :string!,
        "actor!": { kind: :string!, email: :string },
        detail: { note: :string!, extra: :string },
        targets: [[ target_id: :uuid!, role: :string ]],
        "lines!": [[ sku: :string!, quantity: :integer ]]
      }
    )
    schema = spec.schema

    assert_equal %w[title actor lines], schema[:required]
    assert_equal %w[kind], schema.dig(:properties, "actor", :required)
    assert_equal %w[note], schema.dig(:properties, "detail", :required)
    assert_nil schema.dig(:properties, "detail", :properties, "extra", :required)
    assert_equal %w[target_id], schema.dig(:properties, "targets", :items, :required)
    assert_equal %w[sku], schema.dig(:properties, "lines", :items, :required)
    assert_includes schema.dig(:properties).keys, "actor"
  end

  test "permit returns values for required-marked nested and array keys with enforcement off" do
    spec = OpenApiGenerator::InputSpec.new(
      action: :create,
      permit: { "actor!": { kind: :string! }, "lines!": [[ sku: :string! ]] }
    )
    params = ActionController::Parameters.new(actor: { kind: "x", ignored: 1 }, lines: [{ sku: "a" }])

    assert_equal({ actor: { kind: "x" }, lines: [{ sku: "a" }] }, spec.permit(params))
  end

  test "omits required when nothing is marked" do
    spec = OpenApiGenerator::InputSpec.new(action: :create, permit: { detail: { note: :string } })

    assert_not spec.schema.key?(:required)
    assert_not spec.schema.dig(:properties, "detail").key?(:required)
  end
end

class OpenApiGeneratorEnforceRequiredTest < ActiveSupport::TestCase
  setup { @original = OpenApiGenerator.config.enforce_required }
  teardown { OpenApiGenerator.config.enforce_required = @original }

  def spec(wrapped_in: nil)
    OpenApiGenerator::InputSpec.new(
      action: :create,
      wrapped_in: wrapped_in,
      permit: { title: :string!, done: :boolean!, note: :string, detail: { inner: :string! } }
    )
  end

  test "defaults to false and a non-boolean value is rejected" do
    assert_equal false, OpenApiGenerator::Configuration.new.enforce_required
    assert_raises(ArgumentError) { OpenApiGenerator.config.enforce_required = "yes" }
    assert_raises(ArgumentError) { OpenApiGenerator.config.enforce_required = nil }
  end

  test "off by default leaves missing required fields alone" do
    assert_equal({ note: "n" }, spec.permit(ActionController::Parameters.new(note: "n")))
  end

  test "on raises ParameterMissing for a missing or nil top-level required field" do
    OpenApiGenerator.config.enforce_required = true

    error = assert_raises(ActionController::ParameterMissing) { spec.permit(ActionController::Parameters.new(done: true)) }
    assert_equal "title", error.param
    error = assert_raises(ActionController::ParameterMissing) { spec.permit(ActionController::Parameters.new(title: nil, done: true)) }
    assert_equal "title", error.param
    error = assert_raises(ActionController::ParameterMissing) { spec.permit(ActionController::Parameters.new(title: "t")) }
    assert_equal "done", error.param
  end

  test "on lets false and empty string through to the model" do
    OpenApiGenerator.config.enforce_required = true

    assert_equal({ title: "", done: false }, spec.permit(ActionController::Parameters.new(title: "", done: false)))
  end

  test "on does not enforce nested required fields" do
    OpenApiGenerator.config.enforce_required = true
    params = ActionController::Parameters.new(title: "t", done: true, detail: { other: "x" })

    assert_equal({ title: "t", done: true, detail: {} }, spec.permit(params))
  end

  test "on treats a wrong-shaped value that permit drops as missing" do
    OpenApiGenerator.config.enforce_required = true
    params = ActionController::Parameters.new(title: { nested: "x" }, done: true)

    error = assert_raises(ActionController::ParameterMissing) { spec.permit(params) }
    assert_equal "title", error.param
  end

  test "on does not let a path parameter satisfy a flat body field" do
    OpenApiGenerator.config.enforce_required = true
    flat = OpenApiGenerator::InputSpec.new(action: :update, permit: { id: :string!, note: :string })
    params = ActionController::Parameters.new(id: "from-path", note: "n")

    assert_raises(ActionController::ParameterMissing) { flat.permit(params, path_keys: [ :id ]) }
    assert_equal({ id: "from-body", note: "n" },
      flat.permit(ActionController::Parameters.new(id: "from-body", note: "n"), path_keys: []))
  end

  test "on enforces wrapped and flat bodies" do
    OpenApiGenerator.config.enforce_required = true
    wrapped = spec(wrapped_in: :card)

    assert_equal({ title: "t", done: false }, wrapped.permit(ActionController::Parameters.new(card: { title: "t", done: false })))
    assert_raises(ActionController::ParameterMissing) { wrapped.permit(ActionController::Parameters.new(card: { done: false })) }
    assert_equal({ title: "t", done: false }, wrapped.permit(ActionController::Parameters.new(title: "t", done: false)))
    assert_raises(ActionController::ParameterMissing) { wrapped.permit(ActionController::Parameters.new(done: false)) }
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
    assert_equal "get_widget", operation[:operationId]
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

  test "audits write operations without request body declarations" do
    routes = [
      OpenApiGenerator::RouteDiscovery::RouteInfo.new("POST", "/api/widgets", "api/widgets", "create"),
      OpenApiGenerator::RouteDiscovery::RouteInfo.new("POST", "/api/gadgets", "api/gadgets", "create")
    ]
    config = OpenApiGenerator::Configuration.new
    config.ignored_paths = []
    config.included_base_controllers = ["Api::AuthenticatedBaseController"]

    offenses = OpenApiGenerator::RouteDiscovery.stub(:call, routes) do
      OpenApiGenerator::Completeness.audit(config: config)
    end

    assert_equal 1, offenses.size
    assert_equal "POST", offenses.first.verb
    assert_equal "/api/widgets", offenses.first.path
    assert_equal "Api::WidgetsController", offenses.first.controller
  end

  test "audit skips ignored controllers unless include_ignored is true" do
    routes = [OpenApiGenerator::RouteDiscovery::RouteInfo.new("POST", "/api/hidden_things", "api/hidden_things", "create")]
    config = OpenApiGenerator::Configuration.new
    config.ignored_paths = []

    default = OpenApiGenerator::RouteDiscovery.stub(:call, routes) { OpenApiGenerator::Completeness.audit(config: config) }
    audited = OpenApiGenerator::RouteDiscovery.stub(:call, routes) do
      OpenApiGenerator::Completeness.audit(config: config, include_ignored: true)
    end

    assert_empty default
    assert_equal ["Api::HiddenThingsController"], audited.map(&:controller)
    assert_equal "/api/hidden_things", audited.first.path
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

class OpenApiGeneratorResponseSchemaTest < ActiveSupport::TestCase
  def controller_with(&block)
    controller = Class.new(ActionController::API)
    controller.include OpenApiGenerator::ControllerDSL
    controller.class_eval(&block) if block
    controller
  end

  def build(controller, action, config: OpenApiGenerator::Configuration.new, registry: OpenApiGenerator::SchemaRegistry.new)
    responses = OpenApiGenerator::ResponseBuilder.build(config, controller, action, {}, registry)
    [responses, registry.to_h]
  end

  def schema_of(responses)
    responses.values.first[:content]["application/json"][:schema]
  end

  def item_serializer(name: "GadgetSerializer", collection: false)
    Class.new do
      define_singleton_method(:name) { name }
      define_singleton_method(:open_api_schema) { { type: "object", properties: { id: { type: "string" } } } }
      if collection
        define_singleton_method(:open_api_collection_schema) do
          { type: "object", properties: { data: { type: "array", items: open_api_schema } } }
        end
      end
    end
  end

  test "response_column_denylist defaults to empty and validates its entries" do
    config = OpenApiGenerator::Configuration.new
    assert_equal [], config.response_column_denylist

    config.response_column_denylist = ["a", /token/, :b]
    assert_equal ["a", /token/, "b"], config.response_column_denylist
    assert config.response_column_denied?("a")
    assert config.response_column_denied?("api_token_digest")
    refute config.response_column_denied?("title")

    assert_raises(ArgumentError) { config.response_column_denylist = [1] }
    assert_raises(ArgumentError) { config.response_column_denylist = [nil] }
  end

  test "the denylist filters the model fallback only" do
    config = OpenApiGenerator::Configuration.new
    config.response_column_denylist = [/\Adesc/]
    controller = controller_with { api_response :show, model: Gadget }

    responses, schemas = build(controller, :show, config: config)

    assert_equal({ "$ref" => "#/components/schemas/Gadget" }, schema_of(responses))
    assert_equal %w[id title created_at updated_at], schemas["Gadget"][:properties].keys
  end

  test "the denylist never filters serializer schemas" do
    config = OpenApiGenerator::Configuration.new
    config.response_column_denylist = ["title"]
    serializer = Class.new do
      def self.name = "GadgetSerializer"
      def self.open_api_schema = { type: "object", properties: { title: { type: "string" } } }
    end
    controller = controller_with { api_response :show, serializer: serializer }
    _responses, schemas = build(controller, :show, config: config)
    assert_equal [:title], schemas["Gadget"][:properties].keys
  end

  test "the denylist never filters request schemas built through SpecBuilder" do
    route = OpenApiGenerator::RouteDiscovery::RouteInfo.new("POST", "/api/gadgets", "api/gadgets", "create")
    config = OpenApiGenerator::Configuration.new
    config.ignored_paths = []
    config.included_base_controllers = ["Api::AuthenticatedBaseController"]
    config.response_column_denylist = ["title", "description"]

    spec = OpenApiGenerator::RouteDiscovery.stub(:call, [route]) do
      OpenApiGenerator::SpecBuilder.call(config: config)
    end

    assert spec[:components][:schemas]["GadgetCreateRequest"][:properties].key?("title")
    refute spec[:components][:schemas]["Gadget"][:properties].key?("title")
  end

  test "a model reused across actions registers one schema" do
    config = OpenApiGenerator::Configuration.new
    config.response_column_denylist = ["description"]
    controller = controller_with do
      api_response :index, model: Gadget, collection: true
      api_response :show, model: Gadget
      api_response :create, model: Gadget, envelope: :data
    end
    registry = OpenApiGenerator::SchemaRegistry.new

    %i[index show create].each { |action| build(controller, action, config: config, registry: registry) }

    refute registry.to_h["Gadget"][:properties].key?("description")
  end

  test "output is unchanged when no envelope is set" do
    controller = controller_with do
      api_response :show, model: Gadget
      api_response :index, model: Gadget, collection: true
    end

    responses, schemas = build(controller, :show)
    assert_equal({ "$ref" => "#/components/schemas/Gadget" }, schema_of(responses))
    responses, = build(controller, :index)
    assert_equal({ type: "array", items: { "$ref" => "#/components/schemas/Gadget" } }, schema_of(responses))
    assert_equal ["Gadget"], schemas.keys
  end

  test "envelope data wraps a model schema" do
    controller = controller_with do
      api_response :show, model: Gadget, envelope: :data
      api_response :index, model: Gadget, collection: true, envelope: :data
    end
    registry = OpenApiGenerator::SchemaRegistry.new

    show, = build(controller, :show, registry: registry)
    index, = build(controller, :index, registry: registry)
    schemas = registry.to_h

    assert_equal({ "$ref" => "#/components/schemas/GadgetEnvelope" }, schema_of(show))
    assert_equal({ type: "object", properties: { data: { "$ref" => "#/components/schemas/Gadget" } }, required: ["data"] }, schemas["GadgetEnvelope"])
    assert_equal({ "$ref" => "#/components/schemas/GadgetListEnvelope" }, schema_of(index))
    assert_equal(
      { type: "object", properties: { data: { type: "array", items: { "$ref" => "#/components/schemas/Gadget" } }, meta: { type: "object" } }, required: ["data"] },
      schemas["GadgetListEnvelope"]
    )
  end

  test "envelope data wraps a serializer item schema and ignores its collection schema" do
    serializer = item_serializer(collection: true)
    controller = controller_with do
      api_response :index, serializer: serializer, collection: true, envelope: :data
    end

    responses, schemas = build(controller, :index)

    assert_equal({ "$ref" => "#/components/schemas/GadgetListEnvelope" }, schema_of(responses))
    assert_equal serializer.open_api_schema, schemas["Gadget"]
    refute schemas.key?("GadgetCollection")
  end

  test "collection uses the serializer collection schema when defined" do
    serializer = item_serializer(collection: true)
    controller = controller_with { api_response :index, serializer: serializer, collection: true }

    responses, schemas = build(controller, :index)

    assert_equal({ "$ref" => "#/components/schemas/GadgetCollection" }, schema_of(responses))
    assert_equal serializer.open_api_collection_schema, schemas["GadgetCollection"]
  end

  test "collection without a serializer collection schema stays an array of the item schema" do
    serializer = item_serializer
    controller = controller_with { api_response :index, serializer: serializer, collection: true }

    responses, = build(controller, :index)

    assert_equal({ type: "array", items: { "$ref" => "#/components/schemas/Gadget" } }, schema_of(responses))
  end

  test "the class-level envelope default is inherited and overridable" do
    parent = controller_with { self.open_api_generator_response_envelope = :data }
    child = Class.new(parent) do
      api_response :show, model: Gadget
      api_response :create, model: Gadget, envelope: :none
    end
    bare = Class.new(parent) do
      self.open_api_generator_response_envelope = :none
      api_response :show, model: Gadget
    end

    assert_equal({ "$ref" => "#/components/schemas/GadgetEnvelope" }, schema_of(build(child, :show).first))
    assert_equal({ "$ref" => "#/components/schemas/Gadget" }, schema_of(build(child, :create).first))
    assert_equal({ "$ref" => "#/components/schemas/Gadget" }, schema_of(build(bare, :show).first))
  end

  test "enveloped and bare use of one model never conflict in the registry" do
    controller = controller_with do
      api_response :show, model: Gadget, envelope: :data
      api_response :create, model: Gadget
      api_response :index, model: Gadget, collection: true, envelope: :data
    end
    registry = OpenApiGenerator::SchemaRegistry.new

    %i[show create index].each { |action| build(controller, action, registry: registry) }

    assert_equal %w[Gadget GadgetEnvelope GadgetListEnvelope].sort, registry.to_h.keys.sort
  end

  test "re-including the DSL in a subclass keeps an inherited envelope default" do
    parent = controller_with { self.open_api_generator_response_envelope = :none }
    child = Class.new(parent) { include OpenApiGenerator::ControllerDSL }

    assert_equal :none, child.open_api_generator_response_envelope
  end

  test "an invalid class-level envelope raises when the schema is built" do
    controller = controller_with do
      self.open_api_generator_response_envelope = :wrap
      api_response :show, model: Gadget
    end

    assert_raises(ArgumentError) { build(controller, :show) }
  end

  test "api_response rejects an unknown envelope" do
    assert_raises(ArgumentError) { controller_with { api_response :show, model: Gadget, envelope: :wrap } }
  end
end
