# frozen_string_literal: true

module Api
  module V1
    class ProjectScope
      def self.resolve_project(principal, project_id)
        principal.resolve_project(project_id)
      end

      def self.memberships(principal)
        scope = principal.user.project_memberships.includes(:project)
        scope = scope.where(project_id: principal.project.id) if principal.project_principal?
        scope
      end

      def self.pages(project)
        project.pages
          .left_joins(:screenshots)
          .select("pages.*, COUNT(screenshots.id) AS version_count")
          .group("pages.id")
          .order(:created_at)
      end

      def self.screenshots(project)
        project.screenshots.includes(:page, :annotations, :screenshot_images).order(created_at: :desc)
      end

      # List reads never serialize attachments, so they stay metadata-light.
      def self.annotations(project)
        Annotation.joins(screenshot: { page: :project })
          .where(projects: { id: project.id })
          .includes(:user, :api_key, :screenshot, annotation_comments: [ :user, :api_key ])
      end

      # Detail reads serialize an attachment row per annotation and per
      # comment, so they preload those rows. The contract payload is plain
      # columns plus a signed record token, so no blob is ever touched.
      def self.annotation_details(project)
        annotations(project).includes(
          :image_attachments,
          annotation_comments: :image_attachments
        )
      end
    end
  end
end
