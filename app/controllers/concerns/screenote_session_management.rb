# frozen_string_literal: true

module ScreenoteSessionManagement
  extend ActiveSupport::Concern

  include RailsSimpleAuth::Controllers::Concerns::SessionManagement

  class InactiveUser < StandardError; end

  included do
    rescue_from InactiveUser, with: :handle_inactive_session_user
  end

  private

  def client_ip
    request.remote_ip
  end

  def set_current_user
    RailsSimpleAuth::Current.user = nil
    RailsSimpleAuth::Current.session = nil
    return unless (session_token = cookies.signed.permanent[:session_token])

    session_record = RailsSimpleAuth.configuration.session_class
      .includes(:user)
      .active
      .find_by(id: session_token)

    if session_record&.user&.access_active?
      RailsSimpleAuth::Current.user = session_record.user
      RailsSimpleAuth::Current.session = session_record
    else
      delete_session_cookie
    end
  end

  def create_session_for(user)
    raise InactiveUser, "inactive users cannot create browser sessions" unless user&.persisted?

    issuance = lambda do
      User.transaction do
        locked_user = AuthorityLock.user!(user)
        raise InactiveUser, "inactive users cannot create browser sessions" unless locked_user.access_active?

        session_record = locked_user.sessions.create!(
          ip_address: client_ip,
          user_agent: request.user_agent
        )
        [ locked_user, session_record ]
      end
    end
    locked_user, session_record = if ApplicationRecord.connection.transaction_open?
      issuance.call
    else
      DatabaseRetry.call { issuance.call }
    end

    cookies.signed.permanent[:session_token] = {
      value: session_record.id,
      httponly: true,
      secure: Screenote::Deployment.current.secure_cookies?,
      same_site: :lax
    }

    RailsSimpleAuth::Current.user = locked_user
    RailsSimpleAuth::Current.session = session_record

    session_record
  rescue ActiveRecord::RecordNotFound
    raise InactiveUser, "inactive users cannot create browser sessions"
  end

  def replace_current_session_with(user)
    return RailsSimpleAuth::Current.session if current_session_belongs_to?(user)

    destroy_current_session
    create_session_for(user)
  end

  def destroy_current_session
    if (session_token = cookies.signed.permanent[:session_token])
      RailsSimpleAuth.configuration.session_class.find_by(id: session_token)&.destroy
    end

    delete_session_cookie
    RailsSimpleAuth::Current.user = nil
    RailsSimpleAuth::Current.session = nil
  end

  def current_session_belongs_to?(user)
    return false unless user&.persisted?

    session_record = RailsSimpleAuth::Current.session
    RailsSimpleAuth::Current.user&.id == user.id &&
      session_record&.user_id == user.id &&
      RailsSimpleAuth.configuration.session_class.active.exists?(id: session_record.id, user_id: user.id)
  end

  def authentication_link_context(expected_purpose = nil)
    value = session[:authentication_link]
    return unless value.is_a?(Hash)

    token_id = value["token_id"] || value[:token_id]
    purpose = value["purpose"] || value[:purpose]
    return unless token_id.is_a?(Integer) && token_id.positive?
    return unless purpose.is_a?(String) && AuthenticationToken.purposes.key?(purpose)
    return if expected_purpose && purpose != expected_purpose.to_s

    { token_id: token_id, purpose: purpose }.freeze
  end

  def store_authentication_link_context(token_id:, purpose:)
    purpose = purpose.to_s
    raise ArgumentError, "invalid authentication-link context" unless token_id.is_a?(Integer) && token_id.positive?
    raise ArgumentError, "invalid authentication-link context" unless AuthenticationToken.purposes.key?(purpose)

    session[:authentication_link] = { "token_id" => token_id, "purpose" => purpose }
  end

  def clear_authentication_link_context
    session.delete(:authentication_link)
  end

  def delete_session_cookie
    cookies.delete(
      :session_token,
      secure: Screenote::Deployment.current.secure_cookies?,
      same_site: :lax
    )
  end

  def handle_inactive_session_user
    delete_session_cookie
    RailsSimpleAuth::Current.user = nil
    RailsSimpleAuth::Current.session = nil
    redirect_to new_session_path, alert: "Account access is unavailable."
  end
end
