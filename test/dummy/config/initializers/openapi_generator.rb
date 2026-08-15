OpenApiGenerator.configure do |config|
  config.included_base_controllers = ["Api::AuthenticatedBaseController"]
  config.security_schemes = { bearerAuth: { type: "http", scheme: "bearer" } }
  config.security = [{ bearerAuth: [] }]
end
