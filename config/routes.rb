
OpenApiGenerator::Engine.routes.draw do
  get "/spec.json", to: "open_api#json"
  get "/spec.yaml", to: "open_api#yaml"
  get "/routes.json", to: "open_api#routes"
end
