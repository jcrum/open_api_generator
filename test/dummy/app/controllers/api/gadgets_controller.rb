module Api
  class GadgetsController < AuthenticatedBaseController
    swagger :index, summary: "List gadgets"
  end
end
