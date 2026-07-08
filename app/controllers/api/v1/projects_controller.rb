# frozen_string_literal: true

module Api
  module V1
    class ProjectsController < Api::BaseController
      def index
        return unless require_scope!("mcp_read")

        if oauth_authenticated?
          memberships = current_user.project_memberships.includes(:project).to_a
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
    end
  end
end
