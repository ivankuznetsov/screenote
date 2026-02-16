# frozen_string_literal: true

module Oauth
  class AuthorizationsController < Doorkeeper::AuthorizationsController
    layout "auth"
  end
end
