# frozen_string_literal: true

module Oauth
  # Consent screens (browser authorization and device approval) let the user
  # bind the grant to their account or to one project. Including controllers
  # define `principal_consent_template`, the view that re-renders the choice.
  module PrincipalSelection
    extend ActiveSupport::Concern

    INVALID_PRINCIPAL_SELECTION = "Choose your account or a project you currently belong to."

    private

    def load_principal_projects
      @principal_projects = Current.user.projects.order(:name, :id)
    end

    def render_invalid_principal_selection
      render_principal_selection_error(INVALID_PRINCIPAL_SELECTION)
    end

    def render_dynamic_client_quota_exceeded(error)
      render_principal_selection_error(error.message)
    end

    def render_principal_selection_error(message)
      load_principal_projects
      @selected_principal_project_id = params[:principal_project_id].presence
      @principal_selection_error = message
      render principal_consent_template, status: :unprocessable_entity
    end
  end
end
