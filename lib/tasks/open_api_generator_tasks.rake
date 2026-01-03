require "json"
require "fileutils"

namespace :open_api_generator do
  desc "Generate a JSON OpenAPI spec file"
  task generate: :environment do
    output_path = ENV.fetch("OUTPUT", Rails.root.join("openapi.json"))
    config = OpenApiGenerator.config
    spec = OpenApiGenerator::SpecBuilder.call(config: config)

    FileUtils.mkdir_p(File.dirname(output_path))
    File.write(output_path, JSON.pretty_generate(spec))
  end
end
