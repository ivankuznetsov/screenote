# frozen_string_literal: true

Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.font_src    :self, :data
    policy.img_src     :self, :data, :blob, "https://s3.us-east-1.rabata.io"
    policy.object_src  :none
    policy.script_src  :self, "https://js.honeybadger.io", "https://cdn.jsdelivr.net"
    policy.style_src   :self
    policy.connect_src :self
    policy.frame_src   :none
  end

  # Generate session nonces for permitted importmap and inline scripts.
  config.content_security_policy_nonce_generator = ->(request) { request.session.id.to_s }
  config.content_security_policy_nonce_directives = %w[script-src]
end
