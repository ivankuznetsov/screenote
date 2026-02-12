Rails.application.routes.draw do
  rails_simple_auth_routes

  resources :projects do
    resources :screenshots do
      resources :annotations, only: %i[create update destroy]
    end
    resources :api_keys, only: %i[index new create destroy]
  end

  # Health check for load balancers
  get "up" => "rails/health#show", as: :rails_health_check

  root "projects#index"
end
