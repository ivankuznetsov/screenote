# frozen_string_literal: true

deployment = Screenote::Deployment.current

Honeybadger.configure do |config|
  config.before_notify do |notice|
    Screenote::Monitoring.sanitize_notice!(notice)
  end if deployment.self_hosted? && deployment.monitoring?
end
