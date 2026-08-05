# frozen_string_literal: true

deployment = Screenote::Deployment.current

if deployment.mail_configuration.fetch(:provider) == :resend
  Resend.configure do |config|
    config.api_key = deployment.mail_configuration[:api_key]
  end
end
