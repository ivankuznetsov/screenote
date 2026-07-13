# frozen_string_literal: true

module Api
  module V1
    class ProjectsController < Api::BaseController
      def index
        return unless require_scope!("mcp_read")

        if oauth_authenticated?
          memberships = current_user.project_memberships.includes(:project)
          if current_oauth_token.project_id.present?
            project = require_current_project!(current_oauth_token.project_id)
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

        if current_oauth_token.project_id.present?
          render_error("Project-scoped OAuth tokens cannot create projects", code: "forbidden", status: :forbidden)
          return
        end

        project = current_user.with_lock do
          unless current_user.can_create_project?
            render_error(
              "Project limit reached for the current plan",
              code: "project_limit_reached",
              status: :forbidden
            )
            return
          end

          current_user.owned_projects.create!(project_params)
        end

        render json: {
          project: Api::V1::ContractSerializer.project(project, screenshot_count: 0).merge(role: "owner")
        }, status: :created
      end

      private

      def project_params
        params.permit(:name)
      end
    end
  end
end
