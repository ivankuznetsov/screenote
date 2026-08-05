# frozen_string_literal: true

# Creates one Screenshot with N ScreenshotImages (one per viewport) and returns
# signed upload URLs for each. Image bytes never enter the MCP transport.
class CreateMultiViewportScreenshotTool < ApplicationTool
  tool_name "create_multi_viewport_screenshot"
  description "Create a screenshot with one or more viewport variants (desktop, tablet, mobile). Returns signed upload URLs for each variant — PUT each binary separately."
  mcp_action scope: :mcp_write, read_only: false, destructive: false, idempotent: false, open_world: false

  arguments do
    required(:project_id).filled(:integer).description("The project ID")
    required(:title).filled(:string).description("Title/version label for the screenshot")
    optional(:page_name).filled(:string).description("Page to group this screenshot under (default: same as title)")
    optional(:snapshot_id).filled(:integer).description("Snapshot ID to link this screenshot to. Must belong to the same project.")
    required(:viewports).description("Array of { viewport: desktop|tablet|mobile, mime_type: image/png|image/jpeg }, 1-3 entries")
  end

  def call(project_id:, title:, viewports:, page_name: nil, snapshot_id: nil)
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

    # Resolve snapshot outside with_error_handling so the early-exit on a
    # missing snapshot stays clear of the StandardError rescue.
    if snapshot_id
      snapshot = current_project.snapshots.find_by(id: snapshot_id)
      return invalid("snapshot not found in project") unless snapshot
    end

    with_error_handling do
      project = current_project
      screenshot = nil
      uploads = nil

      page = Page.find_or_create_by_name!(project, page_name || title)
      begin
        ApplicationRecord.transaction do
          screenshot = page.screenshots.create!(title: title, snapshot: snapshot)
          uploads = normalized.map do |v|
            si = screenshot.screenshot_images.create!(viewport: v[:viewport])
            token = si.generate_token_for(:upload)
            {
              viewport: v[:viewport],
              upload_url: Rails.application.routes.url_helpers.api_screenshot_upload_url(
                screenshot,
                Screenote::Deployment.current.url_options.merge(token: token, mime_type: v[:mime_type])
              ),
              token: token
            }
          end
        end
      rescue ActiveRecord::RecordNotUnique => e
        Screenote::Monitoring.notify(e)
        next invalid("A ScreenshotImage with that viewport already exists for this Screenshot (concurrent request?)")
      rescue ActiveRecord::InvalidForeignKey => e
        # TOCTOU: snapshot existed at the pre-check but was destroyed before
        # the INSERT landed. Surface the same envelope as the pre-check so
        # agents can rely on a stable error shape.
        Screenote::Monitoring.notify(e)
        next invalid("snapshot not found in project")
      end

      {
        screenshot_id: screenshot.id,
        snapshot_id: screenshot.snapshot_id,
        page_id: page.id,
        annotate_url: Rails.application.routes.url_helpers.screenshot_url(
          screenshot,
          Screenote::Deployment.current.url_options
        ),
        uploads: uploads
      }.to_json
    end
  end

  # Visibility marker: any helper methods added below default to private so
  # subclass authors don't silently expose internals.
  private
end
