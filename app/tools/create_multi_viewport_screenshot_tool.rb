# frozen_string_literal: true

# Creates one Screenshot with N ScreenshotImages (one per viewport) and returns
# one-time upload credentials for each. Image bytes never enter MCP transport.
class CreateMultiViewportScreenshotTool < ApplicationTool
  tool_name "create_multi_viewport_screenshot"
  description "Create one Page version with desktop, tablet, or mobile variants. A Snapshot accepts one Screenshot per Page; use a new Page for a different screen or a new Snapshot for a later version. PUT each binary to upload_url with Authorization: Bearer <token> and the returned content_type."
  mcp_action scope: :mcp_write, read_only: false, destructive: false, idempotent: false, open_world: false

  arguments do
    required(:project_id).filled(:integer).description("The project ID")
    required(:title).filled(:string).description("Title/version label for the screenshot")
    optional(:page_name).filled(:string).description("Page to group this screenshot under (default: same as title)")
    optional(:snapshot_id).filled(:integer).description("Snapshot ID for this capture run. It must belong to the same project. Each Snapshot accepts one Screenshot per Page.")
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
        screenshot, uploads = create_screenshot_with_uploads!(
          page: page,
          title: title,
          snapshot: snapshot,
          viewports: normalized
        )
      rescue ActiveRecord::RecordNotUnique => e
        Screenote::Monitoring.notify(e)
        next invalid("A ScreenshotImage with that viewport already exists for this Screenshot (concurrent request?)")
      rescue ActiveRecord::RecordNotFound, ActiveRecord::InvalidForeignKey => e
        # TOCTOU: snapshot existed at the pre-check but was destroyed before
        # validation locked it or the INSERT landed. Surface the same envelope as the pre-check so
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

  def create_screenshot_with_uploads!(page:, title:, snapshot:, viewports:)
    screenshot = nil
    uploads = nil
    ApplicationRecord.transaction do
      screenshot = page.screenshots.create!(title: title, snapshot: snapshot)
      uploads = viewports.map do |viewport|
        image = screenshot.screenshot_images.create!(viewport: viewport[:viewport])
        {
          viewport: viewport[:viewport],
          upload_url: Rails.application.routes.url_helpers.api_screenshot_upload_url(
            screenshot,
            Screenote::Deployment.current.url_options
          ),
          token: image.generate_token_for(:upload),
          content_type: viewport[:mime_type]
        }
      end
    end
    [ screenshot, uploads ]
  end
end
