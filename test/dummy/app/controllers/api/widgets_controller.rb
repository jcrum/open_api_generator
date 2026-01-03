module Api
  class WidgetsController < ActionController::API
    include OpenApiGenerator::ControllerDSL

    swagger_json!
    swagger_tag "Widgets"

    swagger :index,
      summary: "List widgets",
      parameters: [
        {
          name: "page",
          in: "query",
          required: false,
          schema: { type: "integer", minimum: 1 },
          description: "Optional page offset"
        }
      ],
      responses: {
        "200" => {
          description: "Widgets listed",
          content: {
            "application/json" => {
              schema: {
                type: "array",
                items: {
                  type: "object",
                  properties: {
                    id: { type: "integer" },
                    name: { type: "string" }
                  }
                }
              }
            }
          }
        }
      }

    swagger :show,
      summary: "Fetch a widget",
      parameters: [
        {
          name: "id",
          in: "path",
          required: true,
          schema: { type: "integer" },
          description: "Widget ID"
        }
      ],
      responses: {
        "200" => { description: "Widget details returned" },
        "404" => { description: "Widget not found" }
      }

    def index
      render json: [{ id: 1, name: "Example Widget" }]
    end

    def show
      render json: { id: params[:id].to_i, name: "Example Widget" }
    end
  end
end
