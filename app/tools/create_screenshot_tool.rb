# frozen_string_literal: true

class CreateScreenshotTool < ApplicationTool
  tool_name "create_screenshot"
  description "Upload a screenshot for human annotation. Returns a URL where the human can leave Figma-style comments."

  MAX_BASE64_SIZE = 28 * 1024 * 1024 # ~28MB base64 ≈ ~20MB decoded

  arguments do
    required(:project_id).filled(:integer).description("The project ID")
    required(:title).filled(:string).description("Title/version label for the screenshot")
    required(:image_base64).filled(:string).description("Base64-encoded PNG or JPEG image data")
    optional(:page_name).filled(:string).description("Page to group this screenshot under (default: same as title)")
    optional(:mime_type).filled(:string).description("Image MIME type: image/png or image/jpeg (default: image/png)")
  end

  def call(project_id:, title:, image_base64:, page_name: nil, mime_type: "image/png")
    error = require_project(project_id)
    return error if error

    unless mime_type.in?(Screenshot::ALLOWED_CONTENT_TYPES)
      return { error: "invalid_mime_type", message: "Must be image/png or image/jpeg" }.to_json
    end

    if image_base64.bytesize > MAX_BASE64_SIZE
      return { error: "file_too_large", message: "Image exceeds 20MB limit" }.to_json
    end

    with_error_handling do
      project = current_project
      image_data = Base64.decode64(image_base64)

      page = Page.find_or_create_by_name!(project, page_name || title)
      screenshot = page.screenshots.create!(title: title)
      screenshot.image.attach(
        io: StringIO.new(image_data),
        filename: "screenshot.#{mime_type == 'image/jpeg' ? 'jpg' : 'png'}",
        content_type: mime_type
      )

      url = Rails.application.routes.url_helpers.screenshot_url(screenshot)

      { screenshot_id: screenshot.id, page_id: page.id, annotate_url: url }.to_json
    end
  end
end
