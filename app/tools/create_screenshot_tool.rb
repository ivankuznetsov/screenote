# frozen_string_literal: true

class CreateScreenshotTool < ApplicationTool
  tool_name "create_screenshot"
  description "Upload a screenshot for human annotation. Returns a URL where the human can leave Figma-style comments."

  arguments do
    required(:title).filled(:string).description("Title for the screenshot")
    required(:image_base64).filled(:string).description("Base64-encoded PNG or JPEG image data")
    optional(:mime_type).filled(:string).description("Image MIME type: image/png or image/jpeg (default: image/png)")
  end

  def call(title:, image_base64:, mime_type: "image/png")
    project = current_project
    image_data = Base64.decode64(image_base64)

    screenshot = project.screenshots.create!(title: title)
    screenshot.image.attach(
      io: StringIO.new(image_data),
      filename: "screenshot.#{mime_type == 'image/jpeg' ? 'jpg' : 'png'}",
      content_type: mime_type
    )

    url = Rails.application.routes.url_helpers.project_screenshot_url(
      project, screenshot, host: ENV.fetch("APP_HOST", "localhost:3005")
    )

    { screenshot_id: screenshot.id, annotate_url: url }.to_json
  end
end
