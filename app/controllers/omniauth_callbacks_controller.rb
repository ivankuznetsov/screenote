# frozen_string_literal: true

class OmniauthCallbacksController < RailsSimpleAuth::OmniauthCallbacksController
  def create
    auth_hash = request.env["omniauth.auth"]
    provider = params[:provider]

    unless RailsSimpleAuth.configuration.oauth_provider_enabled?(provider)
      redirect_to new_session_path, alert: "OAuth provider not enabled."
      return
    end

    user = user_class.from_oauth(auth_hash)
    display_name = RailsSimpleAuth.configuration.oauth_provider_display_name(provider)

    if user&.persisted?
      destroy_temporary_user_session(user)
      create_session_for(user)
      run_after_sign_in_callback(user)
      redirect_to stored_location_or_default,
                  notice: "Signed in successfully with #{display_name}."
    else
      redirect_to new_session_path, alert: "Could not authenticate with #{display_name}."
    end
  end
end
