# frozen_string_literal: true

module Api
  module V1
    class ProjectScope
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

      def self.annotations(project)
        Annotation.joins(screenshot: { page: :project })
          .where(projects: { id: project.id })
          .includes(:user, :screenshot, :annotation_comments)
      end
    end
  end
end
