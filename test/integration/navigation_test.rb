require "test_helper"

class NavigationTest < ActionDispatch::IntegrationTest
  setup do
    Rails.cache.clear
    OpenApiGenerator.instance_variable_set(:@config, nil)
    OpenApiGenerator.configure do |cfg|
      cfg.title = "Dummy API"
      cfg.version = "1.0.0"
      cfg.cache_enabled = false
      cfg.servers = [{ url: "/" }]
      cfg.ignored_paths = [%r{^/rails}]
    end
  end

  test "serves OpenAPI JSON for widgets" do
    get "/doc/spec.json"

    assert_response :success

    spec = JSON.parse(response.body)
    assert_equal "Dummy API", spec.dig("info", "title")
    assert_equal "1.0.0", spec.dig("info", "version")

    index_operation = spec.dig("paths", "/api/widgets", "get")
    assert_equal "List widgets", index_operation["summary"]
    assert_equal "Widgets", index_operation["tags"].first

    show_operation = spec.dig("paths", "/api/widgets/{id}", "get")
    param_names = show_operation["parameters"].map { |param| param["name"] }
    assert_includes param_names, "id"
    assert_equal ["200", "404"], show_operation["responses"].keys.sort
  end

  test "serves routes introspection" do
    get "/doc/routes.json"

    assert_response :success

    payload = JSON.parse(response.body)
    entry = payload.find { |row| row["controller"] == "Api::WidgetsController" && row["action"] == "show" }
    assert_not_nil entry
    assert_equal "/api/widgets/:id", entry["rails_path"]
    assert_equal "/api/widgets/{id}", entry["open_api_path"]
    required_names = entry["required_parameters"].map { |param| param["name"] }
    assert_includes required_names, "id"

    index_entry = payload.find { |row| row["controller"] == "Api::WidgetsController" && row["action"] == "index" }
    assert_not_nil index_entry
    optional_names = index_entry["optional_parameters"].map { |param| param["name"] }
    assert_includes optional_names, "page"
  end
end
