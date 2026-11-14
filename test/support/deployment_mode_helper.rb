# frozen_string_literal: true

module DeploymentModeHelper
  VALID_MODES = %w[saas self_hosted].freeze

  def require_deployment_mode!(expected)
    expected = expected.to_s
    raise ArgumentError, "unknown Screenote deployment mode: #{expected.inspect}" unless VALID_MODES.include?(expected)

    configured = Screenote::Deployment.current.edition.to_s
    required = ENV["SCREENOTE_REQUIRED_MODE"].presence

    if required
      assert_includes VALID_MODES, required, "SCREENOTE_REQUIRED_MODE must name a supported edition"
      assert_equal expected, required,
        "this test belongs to the #{expected} suite, but the matrix required #{required}"
      assert_equal expected, configured,
        "SCREENOTE_EDITION booted as #{configured}; refusing to claim #{expected} coverage"
    elsif configured != expected
      skip "run with SCREENOTE_EDITION=#{expected}"
    end
  end

  def mail_disabled_deployment
    Screenote::Deployment.new(
      {
        "SCREENOTE_EDITION" => "self_hosted",
        "SCREENOTE_BASE_URL" => "http://screenote.internal"
      },
      production: false
    )
  end
end
