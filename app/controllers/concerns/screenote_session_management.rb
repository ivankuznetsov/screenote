# frozen_string_literal: true

module ScreenoteSessionManagement
  extend ActiveSupport::Concern

  include RailsSimpleAuth::Controllers::Concerns::SessionManagement

  private

  def client_ip
    request.remote_ip
  end

  def create_session_for(user)
    session_record = user.sessions.create!(
      ip_address: client_ip,
      user_agent: request.user_agent
    )

    cookies.signed.permanent[:session_token] = {
      value: session_record.id,
      httponly: true,
      secure: Screenote::Deployment.current.secure_cookies?,
      same_site: :lax
    }

    RailsSimpleAuth::Current.user = user
    RailsSimpleAuth::Current.session = session_record

    session_record
  end

  def destroy_current_session
    if (session_token = cookies.signed.permanent[:session_token])
      RailsSimpleAuth.configuration.session_class.find_by(id: session_token)&.destroy
    end

    cookies.delete(
      :session_token,
      secure: Screenote::Deployment.current.secure_cookies?,
      same_site: :lax
    )
    RailsSimpleAuth::Current.user = nil
    RailsSimpleAuth::Current.session = nil
  end
end
