# frozen_string_literal: true

module Api
  module V1
    class MeController < Api::V1::BaseController
      def show
        render json: {
          id: current_user.id,
          email: current_user.email
        }
      end
    end
  end
end
