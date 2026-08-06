# frozen_string_literal: true

module Oauth
  class AuthorizationsController < Doorkeeper::AuthorizationsController
    OAUTH_REQUEST_FIELDS = %i[
      client_id
      code_challenge
      code_challenge_method
      response_type
      response_mode
      redirect_uri
      scope
      state
    ].freeze

    layout "auth"

    def new
      load_principal_projects
      @selected_principal_project_id = nil
      super
    end

    def create
      # Validate the OAuth request before considering the consent selection.
      # Incoming principal_kind/project_id parameters never reach Doorkeeper.
      return super unless pre_auth.authorizable?

      application = pre_auth.client.application
      DynamicClientRegistration.with_application_lock(application) do
        DynamicClientAuthorizationQuota.authorize(user: Current.user, application:) do
          selected_project_id = params[:principal_project_id].presence
          unless selected_project_id
            next PrincipalBinding.with_locked_user(user: Current.user) do |valid|
              if valid
                @server_principal_attributes = { principal_kind: "user", project_id: nil }
                @pre_auth = nil
                super()
              else
                render_invalid_principal_selection
              end
            end
          end

          PrincipalBinding.with_locked_project(user: Current.user, project_id: selected_project_id) do |valid|
            if valid
              @server_principal_attributes = { principal_kind: "project", project_id: selected_project_id }
              @pre_auth = nil
              super()
            else
              render_invalid_principal_selection
            end
          end
        end
      end
    rescue DynamicClientAuthorizationQuota::Exceeded => error
      render_dynamic_client_quota_exceeded(error)
    rescue DynamicClientRegistration::ApplicationUnavailable
      render plain: "OAuth client is no longer available.", status: :unprocessable_content
    end

    private

    def pre_auth_params
      request_parameters = params.slice(*OAUTH_REQUEST_FIELDS).permit(*OAUTH_REQUEST_FIELDS)
      request_parameters.merge(server_principal_attributes)
    end

    def server_principal_attributes
      @server_principal_attributes || { principal_kind: "user", project_id: nil }
    end

    def render_invalid_principal_selection
      load_principal_projects
      @selected_principal_project_id = nil
      @principal_selection_error = "Choose your account or a project you currently belong to."
      render :new, status: :unprocessable_entity
    end

    def render_dynamic_client_quota_exceeded(error)
      load_principal_projects
      @selected_principal_project_id = nil
      @principal_selection_error = error.message
      render :new, status: :unprocessable_entity
    end

    def load_principal_projects
      @principal_projects = Current.user.projects.order(:name, :id)
    end

    def after_successful_authorization(context)
      super
      DynamicClientRegistration.mark_used!(pre_auth.client.application)
    end
  end
end
