# frozen_string_literal: true

module Api
  module V1
    class PagesController < Api::BaseController
      def index
        return unless require_scope!("mcp_read")

        project = require_current_project!(params[:project_id])
        return unless project

        render json: {
          pages: Api::V1::ProjectScope.pages(project).map do |page|
            Api::V1::ContractSerializer.page(page, url_options: serializer_url_options)
          end
        }
      end
    end
  end
end
