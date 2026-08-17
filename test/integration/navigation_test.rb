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

    assert_response :not_found
  end

end
