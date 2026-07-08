# frozen_string_literal: true

module Api
  module V1
    class ScreenshotsController < Api::BaseController
      def index
        return unless require_scope!("mcp_read")

        project = require_current_project!(params[:project_id])
        return unless project

        limit, offset = pagination_params
        screenshots = Api::V1::ProjectScope.screenshots(project)
        screenshots = screenshots.where(page_id: params[:page_id]) if params[:page_id].present?
        screenshots = screenshots.where(status: params[:status]) if params[:status].present?

        total = screenshots.count
        screenshots = screenshots.limit(limit).offset(offset)

        render json: {
          screenshots: screenshots.map { |screenshot| Api::V1::ContractSerializer.screenshot(screenshot, url_options: url_options) },
          pagination: { total: total, limit: limit, offset: offset }
        }
      end

      def create
        return unless require_scope!("mcp_write")

        project = require_current_project!(params[:project_id])
        return unless project

        image = params[:image]
        unless uploaded_file?(image)
          render_error("Image file is required", code: "validation_failed", status: :unprocessable_entity)
          return
        end

        title = params[:title].presence || "Untitled"
        page = resolve_page(project, title)
        screenshot = Screenshot.create_with_image!(
          page: page, title: title,
          io: image.tempfile,
          filename: image.original_filename,
          content_type: image.content_type
        )

        render json: Api::V1::ContractSerializer.screenshot_create(screenshot, url_options: url_options), status: :created
      end

      private

      def uploaded_file?(image)
        image.respond_to?(:tempfile) &&
          image.respond_to?(:original_filename) &&
          image.respond_to?(:content_type)
      end

      def resolve_page(project, title)
        page_id = params[:page_id].presence || params[:page].presence
        return project.pages.find(page_id) if page_id.to_s.match?(/\A\d+\z/)
        return Page.find_or_create_by_name!(project, page_id) if page_id.present?

        Page.find_or_create_by_name!(project, title)
      end

      def url_options
        { host: request.host, port: request.optional_port, protocol: request.protocol }
      end
    end
  end
end
