Rails.application.routes.draw do
  rails_simple_auth_routes

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
    resources :screenshots do
      resources :annotations, only: %i[create update destroy]
    end
    resources :api_keys, only: %i[index new create destroy]
    resources :invitations, controller: "project_invitations", only: %i[create destroy]
    resources :memberships, controller: "project_memberships", only: %i[index destroy]
  end

  get  "invitations/:token", to: "invitation_acceptances#show", as: :accept_invitation
  post "invitations/:token", to: "invitation_acceptances#create"

  namespace :api do
    put "screenshots/:id/upload", to: "screenshot_uploads#update", as: :screenshot_upload
    namespace :v1 do
      resources :screenshots, only: [ :create ] do
        resources :annotations, only: [ :index ]
      end
    end
  end

  # Health check for load balancers
  get "up" => "rails/health#show", as: :rails_health_check

  # Landing page for unauthenticated users, dashboard for authenticated
  root "pages#landing"
  get "dashboard", to: "projects#index", as: :dashboard
  get "help", to: "pages#help"
end
