# frozen_string_literal: true

Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.font_src    :self, :data, "https://fonts.gstatic.com"
    policy.img_src     :self, :data, :blob, "https://s3.us-east-1.rabata.io"
    policy.object_src  :none
    policy.script_src  :self, "https://js.honeybadger.io", "https://cdn.jsdelivr.net"
    policy.style_src   :self, "https://fonts.googleapis.com"
    policy.connect_src :self
    policy.frame_src   :none
  end

  # Generate random nonces for script-src (covers importmap and inline script tags).
  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src]
end
