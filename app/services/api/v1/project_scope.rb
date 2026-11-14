# frozen_string_literal: true

module Api
  module V1
    # Shared REST and MCP reads. List reads count child rows with one grouped
    # query per page instead of loading them, so their query budget stays flat
    # however many screenshots, annotations, or comments a project holds.
    class ProjectScope
      def self.resolve_project(principal, project_id)
        principal.resolve_project(project_id)
      end

      def self.memberships(principal)
        scope = principal.user.project_memberships.includes(:project)
        scope = scope.where(project_id: principal.project.id) if principal.project_principal?
        scope
      end

      # { project_id => screenshot count }; projects without screenshots are absent.
      def self.screenshot_counts(project_ids)
        Screenshot.joins(:page).where(pages: { project_id: project_ids }).group("pages.project_id").count
      end

      def self.pages(project)
        project.pages
          .left_joins(:screenshots)
          .select("pages.*, COUNT(screenshots.id) AS version_count")
          .group("pages.id")
          .order(:created_at)
      end

      # Each listed version prints its image variants, including whether the
      # blob is attached, so the attachment rows are preloaded with them.
      def self.screenshots(project)
        project.screenshots.includes(:page, screenshot_images: :image_attachment).order(created_at: :desc)
      end

      # { screenshot_id => { total:, unresolved: } }; screenshots without
      # annotations are absent.
      def self.annotation_counts(screenshot_ids)
        Annotation.where(screenshot_id: screenshot_ids).group(:screenshot_id, :status).count
          .each_with_object({}) do |((screenshot_id, status), count), counts|
            tally = counts[screenshot_id] ||= { total: 0, unresolved: 0 }
            tally[:total] += count
            tally[:unresolved] += count if status == "open"
          end
      end

      # Every annotation lookup is confined to the project. Single finds that
      # precede a write load the annotation row and nothing else.
      def self.annotations(project)
        Annotation.joins(screenshot: { page: :project }).where(projects: { id: project.id })
      end

      # List reads print the author and a comment total, never the comments
      # or their attachments, so they stay metadata-light.
      def self.annotation_list(project)
        annotations(project).includes(:user, :api_key)
      end

      # { annotation_id => comment count }; annotations without comments are absent.
      def self.comment_counts(annotation_ids)
        AnnotationComment.where(annotation_id: annotation_ids).group(:annotation_id).count
      end

      # Detail reads serialize the screenshot status, every comment with its
      # author, and an attachment row per annotation and per comment, so they
      # preload those rows. The contract payload is plain columns plus a
      # signed record token, so no blob is ever touched.
      def self.annotation_details(project)
        annotation_list(project).includes(
          :screenshot,
          :image_attachments,
          annotation_comments: [ :user, :api_key, :image_attachments ]
        )
      end
    end
  end
end
