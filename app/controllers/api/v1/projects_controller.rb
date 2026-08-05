# frozen_string_literal: true

module Api
  module V1
    class ProjectsController < Api::BaseController
      def index
        return unless require_scope!("mcp_read")

        if oauth_authenticated?
          memberships = Api::V1::ProjectScope.memberships(current_principal)
          if current_principal.project_principal?
            project = require_current_project!(current_principal.project.id)
            return unless project

            memberships = memberships.where(project_id: project.id)
          end
          memberships = memberships.to_a
          screenshot_counts = Screenshot.joins(:page)
            .where(pages: { project_id: memberships.map(&:project_id) })
            .group("pages.project_id").count

          render json: {
            projects: memberships.map do |membership|
              Api::V1::ContractSerializer.project(
                membership.project,
                screenshot_count: screenshot_counts.fetch(membership.project_id, 0)
              ).merge(role: membership.role)
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

      def create
        unless oauth_authenticated?
          render_error("API keys cannot create projects", code: "forbidden", status: :forbidden)
          return
        end

        return unless require_scope!("mcp_write")

        if current_principal.project_principal?
          render_error("Project-scoped OAuth tokens cannot create projects", code: "forbidden", status: :forbidden)
          return
        end

        project = Projects::Create.call(principal: current_principal, attributes: project_params.to_h)

        render json: {
          project: Api::V1::ContractSerializer.project(project, screenshot_count: 0).merge(role: "owner")
        }, status: :created
      rescue Projects::Create::LimitReached
        render_error(
          "Project limit reached for the current plan",
          code: "project_limit_reached",
          status: :forbidden
        )
      rescue Projects::Create::Forbidden
        render_error("This OAuth principal cannot create projects", code: "forbidden", status: :forbidden)
      end

      private

      def project_params
        params.permit(:name)
      end
    end
  end
end
