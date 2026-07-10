# frozen_string_literal: true

module Api
  module V1
    class SnapshotsController < Api::BaseController
      rate_limit to: 60, within: 1.hour, only: :create,
        by: -> {
          if request.authorization.present?
            [ "bearer", Digest::SHA256.hexdigest(request.authorization), params[:project_id] ].join(":")
          else
            [ "ip", request.remote_ip, params[:project_id] ].join(":")
          end
        },
        with: -> { render_error("Too many snapshot preparations", code: "rate_limited", status: :too_many_requests) }

      rescue_from Snapshots::PrepareUpload::Error do |error|
        status = error.is_a?(Snapshots::PrepareUpload::Conflict) ? :conflict : :unprocessable_entity
        render_error(error.message, code: error.code, status: status, details: error.details)
      end

      def create
        return unless require_scope!("mcp_write")

        project = require_current_project!(params[:project_id])
        return unless project

        result = Snapshots::PrepareUpload.call(project: project, payload: prepare_params)
        operation = result.created ? "created" : "resumed"
        render json: Api::V1::ContractSerializer.snapshot_upload(
          result.snapshot,
          operation: operation,
          url_options: url_options
        ), status: result.created ? :created : :ok
      end

      def show
        return unless require_scope!("mcp_read")

        project = require_current_project!(params[:project_id])
        return unless project

        snapshot = project.snapshots.includes(screenshots: [ :page, { screenshot_images: :image_attachment } ]).find(params[:id])
        render json: Api::V1::ContractSerializer.snapshot_upload(
          snapshot,
          operation: "status",
          url_options: url_options
        )
      end

      private

      def prepare_params
        params.permit(
          :version, :git_commit, :taken_at, :manifest_digest,
          entries: [ :page, :title, :viewport, :mime_type, :content_sha256, :file_ref_sha256 ]
        ).to_h
      end

      def url_options
        { host: request.host, port: request.optional_port, protocol: request.protocol }
      end
    end
  end
end
