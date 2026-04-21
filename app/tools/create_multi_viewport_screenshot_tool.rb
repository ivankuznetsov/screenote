# frozen_string_literal: true

# Creates one Screenshot with N ScreenshotImages (one per viewport) and returns
# signed upload URLs for each. The caller PUTs each viewport's binary to its
# `upload_url` with the matching `token`. Image bytes never enter the MCP
# transport — same pattern as the single-viewport `create_screenshot_upload`,
# extended for 1..3 viewports.
class CreateMultiViewportScreenshotTool < ApplicationTool
  tool_name "create_multi_viewport_screenshot"
  description "Create a screenshot with one or more viewport variants (desktop, tablet, mobile). Returns signed upload URLs for each variant — PUT each binary separately."

  arguments do
    required(:project_id).filled(:integer).description("The project ID")
    required(:title).filled(:string).description("Title/version label for the screenshot")
    optional(:page_name).filled(:string).description("Page to group this screenshot under (default: same as title)")
    required(:viewports).description("Array of { viewport: desktop|tablet|mobile, mime_type: image/png|image/jpeg }, 1-3 entries")
  end

  def call(project_id:, title:, viewports:, page_name: nil)
    error = require_project(project_id)
    return error if error

    supported = ScreenshotImage.viewports.keys
    return invalid("viewports must contain 1..#{supported.size} entries") unless (1..supported.size).cover?(viewports.length)

    # FastMcp symbolises top-level hash keys but NOT hashes inside arrays,
    # so over MCP each entry arrives as { "viewport" => "...", "mime_type" => "..." }.
    # Normalize to symbol-key before indexed access.
    normalized = viewports.map do |v|
      v = v.symbolize_keys if v.respond_to?(:symbolize_keys)
      { viewport: v[:viewport], mime_type: v[:mime_type].presence || "image/png" }
    end
    names = normalized.map { |v| v[:viewport] }
    return invalid("viewport must be one of #{supported.join(', ')}") if names.any? { |n| !n.in?(supported) }
    return invalid("viewports must be unique") if names.uniq.length != names.length

    bad_mime = normalized.find { |v| !v[:mime_type].in?(ScreenshotImage::ALLOWED_CONTENT_TYPES) }
    return invalid("mime_type must be image/png or image/jpeg") if bad_mime

    with_error_handling do
      project = current_project
      screenshot = nil
      uploads = nil

      # Wrap Screenshot + ScreenshotImages creation so a partial failure
      # (e.g. mid-loop ScreenshotImage validation error) rolls back the
      # Screenshot too — no orphans with 0 or partial variants. Page is
      # created outside the transaction so a transient failure here doesn't
      # un-create a Page another caller may already be using.
      page = Page.find_or_create_by_name!(project, page_name || title)
      begin
        ApplicationRecord.transaction do
          screenshot = page.screenshots.create!(title: title)
          uploads = normalized.map do |v|
            si = screenshot.screenshot_images.create!(viewport: v[:viewport])
            token = si.generate_token_for(:upload)
            {
              viewport: v[:viewport],
              upload_url: Rails.application.routes.url_helpers.api_screenshot_upload_url(
                screenshot, token: token, mime_type: v[:mime_type]
              ),
              token: token
            }
          end
        end
      rescue ActiveRecord::RecordNotUnique
        # Catch inside with_error_handling so the structured error returns to
        # the agent instead of being swallowed as a generic "internal_error"
        # by the outer StandardError rescue in ApplicationTool.
        return invalid("A ScreenshotImage with that viewport already exists for this Screenshot (concurrent request?)")
      end

      {
        screenshot_id: screenshot.id,
        page_id: page.id,
        annotate_url: Rails.application.routes.url_helpers.screenshot_url(screenshot),
        uploads: uploads
      }.to_json
    end
  end

  private

  def invalid(message)
    { error: "invalid_arguments", message: message }.to_json
  end
end
