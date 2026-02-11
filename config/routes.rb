Rails.application.routes.draw do
  rails_simple_auth_routes

  resources :projects

  # Health check for load balancers
  get "up" => "rails/health#show", as: :rails_health_check

  root "projects#index"
end
