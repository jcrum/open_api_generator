Rails.application.routes.draw do
  mount OpenApiGenerator::Engine => "/doc"

  namespace :api do
    resources :widgets, only: [:index, :show]
    resources :gadgets, only: [:index]
  end
end
