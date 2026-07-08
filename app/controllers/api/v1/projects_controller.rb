# frozen_string_literal: true

module Api
  module V1
    class ProjectsController < Api::BaseController
      def index
        render json: {
          projects: [
            Api::V1::ContractSerializer.project(current_project).merge(role: "api_key")
          ]
        }
      end
    end
  end
end
