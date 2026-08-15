module Api
  class GadgetsController < AuthenticatedBaseController
    swagger :index, summary: "List gadgets"

    api_params :create, wrapped_in: :gadget, model: Gadget, permit: {
      title: :string!,
      description: :string,
      label_ids: [:string]
    }

    def create
      render json: permitted(:create)
    end
  end
end
