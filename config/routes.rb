Rails.application.routes.draw do
  authentication_link_purpose = /(?:invitation|password_reset|magic_link|email_confirmation|account_recovery)/

  get "media/screenshot_images/:id/:variant", to: "media#show",
    as: :screenshot_image_media,
    constraints: { variant: /original|page_card_1x|page_card_2x|project_strip/ }

  if Screenote::Deployment.current.self_hosted?
    resource :bootstrap, only: %i[show create], controller: "bootstrap"
  end

  resource :session, only: %i[new create destroy]

  if Screenote::Deployment.current.saas?
    get "sign_up", to: "registrations#new", as: :sign_up
    post "sign_up", to: "registrations#create"
  end

  if Screenote::Deployment.current.mail?
    get "passwords/new", to: "passwords#new", as: :new_password
    post "passwords", to: "passwords#create", as: :passwords
    get "password-reset", to: "passwords#edit", as: :edit_password
    patch "password-reset", to: "passwords#update", as: :password

    get "confirmations/new", to: "confirmations#new", as: :new_confirmation
    post "confirmations", to: "confirmations#create", as: :confirmations
    get "confirmation", to: "confirmations#show", as: :confirmation

    get "magic-link/new", to: "magic_links#new", as: :magic_link_form
    post "magic-link", to: "magic_links#create", as: :request_magic_link
    get "magic-link", to: "magic_links#show", as: :magic_link
  end

  if RailsSimpleAuth.configuration.oauth_enabled
    get "/auth/:provider/callback", to: "omniauth_callbacks#create", as: :omniauth_callback
    get "/auth/failure", to: "omniauth_callbacks#failure", as: :omniauth_failure
  end

  use_doorkeeper do
    controllers authorizations: "oauth/authorizations", tokens: "oauth/tokens"
    skip_controllers :applications, :authorized_applications, :token_info
  end

  # OAuth 2.1 metadata endpoints (RFC 9728 / RFC 8414)
  get ".well-known/oauth-protected-resource", to: "oauth_metadata#protected_resource"
  get ".well-known/oauth-authorization-server", to: "oauth_metadata#authorization_server"

  # Dynamic Client Registration (RFC 7591)
  post "oauth/register", to: "oauth/registrations#create"

  # OAuth Device Authorization Grant (RFC 8628)
  post "oauth/authorize_device", to: "oauth/device_authorization_requests#create", as: :oauth_authorize_device
  get "oauth/device", to: "oauth/device_authorizations#show", as: :oauth_device
  post "oauth/device", to: "oauth/device_authorizations#update"

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

  get "authentication-links/:purpose", to: "authentication_links#show",
    as: :authentication_link,
    constraints: { purpose: authentication_link_purpose }
  post "authentication-links/:purpose/exchange", to: "authentication_links#exchange",
    as: :exchange_authentication_link,
    constraints: { purpose: authentication_link_purpose }

  get "invitation-acceptance", to: "invitation_acceptances#show", as: :invitation_acceptance
  post "invitation-acceptance", to: "invitation_acceptances#create"

  if Screenote::Deployment.current.self_hosted?
    namespace :instance do
      resources :accounts, only: :index do
        member do
          post :suspend
          post :restore
          post :revoke_credentials
          post :issue_recovery
        end
      end
      post "administrator/transfer", to: "administrators#transfer", as: :administrator_transfer
    end

    get "account-recovery", to: "account_recoveries#show", as: :account_recovery
    post "account-recovery", to: "account_recoveries#create"
  end

  namespace :api do
    put "screenshots/:id/upload", to: "screenshot_uploads#update", as: :screenshot_upload
    namespace :v1 do
      resources :projects, only: [ :index, :create ] do
        resources :pages, only: [ :index ]
        resources :screenshots, only: [ :index ]
        resources :snapshots, only: [ :create, :show ]
        resources :screenshot_images, only: [ :update ]
      end
      resources :screenshots, only: [ :create ] do
        resources :annotations, only: [ :index ]
      end
      resources :annotations, only: [ :show ] do
        resources :comments, controller: "annotation_comments", only: [ :create ]
      end
      post "annotations/:annotation_id/resolve", to: "annotation_resolutions#create",
        as: :annotation_resolve
    end
  end

  if Screenote::Deployment.current.billing?
    resource :subscription, only: :show do
      post :checkout, on: :member
      post :portal, on: :member
    end
    post "stripe/webhooks", to: "stripe_webhooks#create"

    namespace :admin do
      resource :dashboard, only: :show, controller: "dashboard"
    end
  end

  # Health check for load balancers
  get "install.sh", to: "static_pages#install_cli", as: :cli_installer, format: false
  get "up" => "rails/health#show", as: :rails_health_check
  get "ready" => "health#readiness", as: :readiness_check

  # Landing page for unauthenticated users, dashboard for authenticated
  if Screenote::Deployment.current.self_hosted?
    root "bootstrap#show"
  else
    root "static_pages#landing"
  end
  get "dashboard", to: "projects#index", as: :dashboard
  get "help", to: "static_pages#help"
  if Screenote::Deployment.current.saas?
    get "terms", to: "static_pages#terms"
    get "privacy", to: "static_pages#privacy"
  end
end
