class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("MAILER_FROM", "noreply@screenote.app")
  layout "mailer"
end
