# frozen_string_literal: true

class HealthController < ActionController::Base
  def readiness
    render_readiness(Screenote::Readiness.ready?)
  rescue StandardError
    render_readiness(false)
  end

  private

  def render_readiness(ready)
    response.set_header("Cache-Control", "no-store")
    render json: { status: ready ? "ready" : "not_ready" },
      status: ready ? :ok : :service_unavailable
  end
end
