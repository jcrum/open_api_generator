module Api
  class AuthenticatedBaseController < ActionController::Base
    include OpenApiGenerator::ControllerDSL
  end
end
