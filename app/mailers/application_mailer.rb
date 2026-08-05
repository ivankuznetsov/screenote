class ApplicationMailer < ActionMailer::Base
  default from: Screenote::Deployment.current.mail_configuration[:from] || "noreply@localhost"
  layout "mailer"
end
