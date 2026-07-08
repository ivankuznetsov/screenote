# frozen_string_literal: true

module Api
  module V1
    class ProjectsController < Api::BaseController
      def index
        return unless require_scope!("mcp_read")

        if oauth_authenticated?
          render json: {
            projects: current_user.project_memberships.includes(:project).map do |membership|
              Api::V1::ContractSerializer.project(membership.project).merge(role: membership.role)
            end
          }
          return
        end

        render json: {
          projects: [
            Api::V1::ContractSerializer.project(current_project).merge(role: "api_key")
          ]
        }
      end
    end
  end
end
