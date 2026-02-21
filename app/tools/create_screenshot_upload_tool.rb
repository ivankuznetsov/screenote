# frozen_string_literal: true

class CreateScreenshotUploadTool < ApplicationTool
  tool_name "create_screenshot_upload"
  description "Create a screenshot record and get a signed upload URL. Upload the image file directly via curl to the returned URL — no base64 needed."

  arguments do
    required(:project_id).filled(:integer).description("The project ID")
    required(:title).filled(:string).description("Title/version label for the screenshot")
    optional(:page_name).filled(:string).description("Page to group this screenshot under (default: same as title)")
    optional(:mime_type).filled(:string).description("Image MIME type: image/png or image/jpeg (default: image/png)")
  end

  def call(project_id:, title:, page_name: nil, mime_type: "image/png")
    error = require_project(project_id)
    return error if error

    unless mime_type.in?(Screenshot::ALLOWED_CONTENT_TYPES)
      return { error: "invalid_mime_type", message: "Must be image/png or image/jpeg" }.to_json
    end

    with_error_handling do
      project = current_project
      page = Page.find_or_create_by_name!(project, page_name || title)
      screenshot = page.screenshots.create!(title: title)
      token = screenshot.generate_token_for(:upload)

      upload_url = Rails.application.routes.url_helpers.api_screenshot_upload_url(
        screenshot,
        token: token,
        mime_type: mime_type
      )

      annotate_url = Rails.application.routes.url_helpers.screenshot_url(screenshot)

      {
        screenshot_id: screenshot.id,
        page_id: page.id,
        upload_url: upload_url,
        annotate_url: annotate_url
      }.to_json
    end
  end
end
