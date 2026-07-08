Rails.application.routes.draw do
  rails_simple_auth_routes(omniauth_controller: "omniauth_callbacks")

  use_doorkeeper do
    controllers authorizations: "oauth/authorizations"
    skip_controllers :applications, :authorized_applications, :token_info
  end

  # OAuth 2.1 metadata endpoints (RFC 9728 / RFC 8414)
  get ".well-known/oauth-protected-resource", to: "oauth_metadata#protected_resource"
  get ".well-known/oauth-authorization-server", to: "oauth_metadata#authorization_server"

  # Dynamic Client Registration (RFC 7591)
  post "oauth/register", to: "oauth/registrations#create"

  resources :projects do
    resources :pages, only: %i[new create]
    resources :api_keys, only: %i[index new create destroy]
    resources :invitations, controller: "project_invitations", only: %i[create destroy]
    resources :memberships, controller: "project_memberships", only: %i[index destroy]
    get "collaborator_suggestions", to: "collaborator_suggestions#index"
  end

  resources :pages, only: %i[show edit update destroy] do
    resources :screenshots, only: %i[new create]
  end

  resources :screenshots, only: %i[show edit update destroy] do
    member do
      get "viewports/:viewport", to: "screenshots#show", as: :viewport,
          constraints: { viewport: /desktop|tablet|mobile/ }
    end
    resources :annotations, only: %i[create update destroy] do
      resources :annotation_comments, only: %i[create]
    end
  end

  get  "invitations/:token", to: "invitation_acceptances#show", as: :accept_invitation
  post "invitations/:token", to: "invitation_acceptances#create"

  namespace :api do
    put "screenshots/:id/upload", to: "screenshot_uploads#update", as: :screenshot_upload
    namespace :v1 do
      resources :projects, only: [ :index ] do
        resources :pages, only: [ :index ]
        resources :screenshots, only: [ :index ]
      end
      resources :screenshots, only: [ :create ] do
        resources :annotations, only: [ :index ]
      end
      resources :annotations, only: [ :show ] do
        resources :comments, controller: "annotation_comments", only: [ :create ]
      end
    end
  end

  # Billing
  resource :subscription, only: :show do
    post :checkout, on: :member
    post :portal, on: :member
  end
  post "stripe/webhooks", to: "stripe_webhooks#create"

  # Admin
  namespace :admin do
    resource :dashboard, only: :show, controller: "dashboard"
  end

  # Health check for load balancers
  get "up" => "rails/health#show", as: :rails_health_check

  # Landing page for unauthenticated users, dashboard for authenticated
  root "static_pages#landing"
  get "dashboard", to: "projects#index", as: :dashboard
  get "help", to: "static_pages#help"
  get "terms", to: "static_pages#terms"
  get "privacy", to: "static_pages#privacy"
end
