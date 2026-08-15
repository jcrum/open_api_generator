module Api
  class GadgetsController < AuthenticatedBaseController
    swagger :index, summary: "List gadgets"

    api_params :create, wrapped_in: :gadget, model: Gadget, permit: {
      title: :string!,
      description: :string,
      label_ids: [:string]
    }
    api_response :create, status: 201, model: Gadget
    swagger :create,
      operation_id: "create_gadget",
      tool_name: "add_gadget",
      extensions: { idempotent: true, write_scope: "gadgets" }

    def create
      render json: permitted(:create)
    end
  end
end
