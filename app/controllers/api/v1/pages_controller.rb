# frozen_string_literal: true

module Api
  module V1
    class PagesController < Api::BaseController
      def index
        project = require_current_project!(params[:project_id])
        return unless project

        render json: {
          pages: Api::V1::ProjectScope.pages(project).map do |page|
            Api::V1::ContractSerializer.page(page, url_options: url_options)
          end
        }
      end

      private

      def url_options
        { host: request.host, port: request.optional_port, protocol: request.protocol }
      end
    end
  end
end
