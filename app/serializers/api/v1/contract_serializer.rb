# frozen_string_literal: true

module Api
  module V1
    class ContractSerializer
      class << self
        def project(project)
          {
            id: project.id,
            name: project.name,
            screenshot_count: project.screenshots.count,
            created_at: project.created_at.iso8601
          }
        end

        def page(page, url_options: {})
          {
            id: page.id,
            name: page.name,
            version_count: page.version_count.to_i,
            url: routes.page_url(page, url_options),
            created_at: page.created_at.iso8601
          }
        end

        def screenshot(screenshot, url_options: {})
          {
            id: screenshot.id,
            title: screenshot.title,
            page_id: screenshot.page_id,
            page_name: screenshot.page.name,
            status: screenshot.status,
            annotation_count: screenshot.annotations.size,
            unresolved_count: screenshot.annotations.count(&:open?),
            annotate_url: routes.screenshot_url(screenshot, url_options),
            viewports: screenshot.screenshot_images.order(:viewport).map { |image| screenshot_image(image) },
            created_at: screenshot.created_at.iso8601
          }
        end

        def screenshot_create(screenshot, url_options: {})
          {
            screenshot_id: screenshot.id,
            page_id: screenshot.page_id,
            status: screenshot.status,
            annotate_url: routes.screenshot_url(screenshot, url_options),
            image: screenshot_image(screenshot.primary_image)
          }
        end

        def annotation(annotation)
          annotation.as_api_json
        end

        def annotation_detail(annotation, cropped_base64:)
          comments = annotation.annotation_comments.includes(:user, :api_key).order(:created_at).map do |comment|
            annotation_comment(comment, annotation: annotation, include_annotation_id: false)
          end

          annotation(annotation).merge(
            screenshot_status: annotation.screenshot.status,
            cropped_image_base64: cropped_base64,
            mime_type: "image/png",
            comments: comments
          )
        end

        def annotation_comment(comment, annotation: comment.annotation, include_annotation_id: true)
          payload = {
            id: comment.id,
            action: comment.action,
            body: comment.body,
            author: comment.user&.email || comment.api_key&.name || "Unknown",
            created_at: comment.created_at.iso8601
          }
          payload[:annotation_id] = annotation.id if include_annotation_id
          payload
        end

        private

        def screenshot_image(image)
          return nil unless image

          {
            id: image.id,
            viewport: image.viewport,
            status: image.status,
            width: image.width,
            height: image.height,
            attached: image.image.attached?
          }
        end

        def routes
          Rails.application.routes.url_helpers
        end
      end
    end
  end
end
