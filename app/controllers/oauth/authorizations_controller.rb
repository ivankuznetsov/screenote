# frozen_string_literal: true

module Oauth
  class AuthorizationsController < Doorkeeper::AuthorizationsController
    layout "auth"

    before_action :load_projects, only: :new

    private

    def load_projects
      return unless current_resource_owner

      @projects = current_resource_owner.projects
    end
  end
end
