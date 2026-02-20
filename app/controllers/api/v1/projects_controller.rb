# frozen_string_literal: true

module Api
  module V1
    class ProjectsController < Api::V1::BaseController
      def index
        projects = current_user.projects.order(:name)

        render json: {
          projects: projects.map { |p| serialize(p) }
        }
      end

      def create
        unless current_user.can_create_project?
          render json: { error: "Project limit reached. Upgrade to Pro for unlimited projects." }, status: :forbidden
          return
        end

        project = current_user.owned_projects.build(name: params[:name])

        if project.save
          render json: serialize(project), status: :created
        else
          render json: { error: project.errors.full_messages.join(", ") }, status: :unprocessable_entity
        end
      end

      private

      def serialize(project)
        {
          id: project.id,
          name: project.name,
          screenshots_count: project.screenshots.count,
          role: project.role_for(current_user)&.to_s
        }
      end
    end
  end
end
