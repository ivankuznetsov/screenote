# frozen_string_literal: true

class CreateScreenshotUploadTool < ApplicationTool
  tool_name "create_screenshot_upload"
  description "Create a screenshot record and get a signed upload URL. Upload the image file directly via curl to the returned URL — no base64 needed."

  arguments do
    required(:project_id).filled(:integer).description("The project ID")
    required(:title).filled(:string).description("Title for the screenshot")
    optional(:mime_type).filled(:string).description("Image MIME type: image/png or image/jpeg (default: image/png)")
  end

  def call(project_id:, title:, mime_type: "image/png")
    error = require_project(project_id)
    return error if error

    unless mime_type.in?(Screenshot::ALLOWED_CONTENT_TYPES)
      return { error: "invalid_mime_type", message: "Must be image/png or image/jpeg" }.to_json
    end

    with_error_handling do
      project = current_project
      screenshot = project.screenshots.create!(title: title)
      token = screenshot.generate_token_for(:upload)

      upload_url = Rails.application.routes.url_helpers.api_screenshot_upload_url(
        screenshot,
        token: token,
        mime_type: mime_type
      )

      annotate_url = Rails.application.routes.url_helpers.project_screenshot_url(project, screenshot)

      {
        screenshot_id: screenshot.id,
        upload_url: upload_url,
        annotate_url: annotate_url
      }.to_json
    end
  end
end
