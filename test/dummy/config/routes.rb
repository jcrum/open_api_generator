Rails.application.routes.draw do
  mount OpenApiGenerator::Engine => "/doc"

  namespace :api do
    resources :widgets, only: [:index, :show]
  end
end
