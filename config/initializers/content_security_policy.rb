# frozen_string_literal: true

Rails.application.configure do
  deployment = Screenote::Deployment.current

  config.content_security_policy do |policy|
    policy.default_src :self
    font_sources = [ :self, :data ]
    font_sources << "https://fonts.gstatic.com" if deployment.saas?
    policy.font_src(*font_sources)

    # Screenshot bytes are always proxied by the authenticated application
    # controller, so private storage origins never need browser access.
    policy.img_src :self, :data, :blob
    policy.object_src  :none

    script_sources = [ :self ]
    script_sources << "https://cdn.jsdelivr.net" if deployment.saas?
    script_sources << "https://js.honeybadger.io" if deployment.saas? && deployment.monitoring?
    policy.script_src(*script_sources)

    style_sources = [ :self, :unsafe_inline ]
    style_sources << "https://fonts.googleapis.com" if deployment.saas?
    policy.style_src(*style_sources)

    connect_sources = [ :self ]
    connect_sources << "https://cdn.jsdelivr.net" if deployment.saas?
    policy.connect_src(*connect_sources)
    policy.frame_src :none
  end

  # Generate random nonces for script-src (covers importmap and inline script tags).
  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src]
end
