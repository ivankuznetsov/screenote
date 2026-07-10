# frozen_string_literal: true

module Api
  module V1
    class ContractSerializer
      class << self
        def project(project, screenshot_count: project.screenshots.count)
          {
            id: project.id,
            name: project.name,
            screenshot_count: screenshot_count,
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
            viewports: screenshot.screenshot_images.sort_by(&:viewport).map { |image| screenshot_image(image) },
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

        def snapshot_upload(snapshot, operation:, url_options: {})
          entries = snapshot.screenshots.sort_by(&:id).flat_map do |screenshot|
            screenshot.screenshot_images.sort_by { |image| ScreenshotImage.viewports.fetch(image.viewport) }.map do |image|
              {
                screenshot_id: screenshot.id,
                manifest_entry_digest: screenshot.manifest_entry_digest,
                page_id: screenshot.page_id,
                page: screenshot.page.name,
                title: screenshot.title,
                image_id: image.id,
                viewport: image.viewport,
                mime_type: image.expected_content_type,
                content_sha256: image.content_sha256,
                state: screenshot_image_state(image),
                status: image.status,
                attached: image.image.attached?
              }
            end
          end

          {
            operation: operation,
            snapshot_id: snapshot.id,
            project_id: snapshot.project_id,
            manifest_digest: snapshot.manifest_digest,
            git_commit: snapshot.git_commit,
            taken_at: snapshot.taken_at.utc.iso8601(6),
            state: snapshot.aggregate_state,
            review_url: routes.project_url(snapshot.project, url_options.merge(snapshot_id: snapshot.id)),
            entries: entries
          }
        end

        def screenshot_image_upload(image, operation:)
          snapshot = image.screenshot.snapshot
          {
            operation: operation,
            snapshot_id: snapshot.id,
            screenshot_id: image.screenshot_id,
            image_id: image.id,
            viewport: image.viewport,
            state: screenshot_image_state(image),
            status: image.status,
            attached: image.image.attached?,
            snapshot_state: snapshot.aggregate_state
          }
        end

        def annotation(annotation)
          annotation.as_api_json
        end

        def annotation_detail(annotation, cropped_base64:)
          comments = annotation.annotation_comments.sort_by(&:created_at).map do |comment|
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

        def screenshot_image_state(image)
          return "awaiting_upload" unless image.image.attached?
          return "failed" if image.status_failed?
          return "ready" if image.status_ready?

          "processing"
        end

        def routes
          Rails.application.routes.url_helpers
        end
      end
    end
  end
end
