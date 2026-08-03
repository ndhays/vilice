# Thin HTTP surface over the Harness behavior. Each action maps to a coverage axis; the
# logic lives in Harness so it stays testable without a server.
class HarnessController < ApplicationController
  # GET / — hello-world + identity + echoed config.
  def index
    render json: Harness.info
  end

  # GET /healthz — the health gate. 200 when ready, 503 while starting or failing, so
  # Steward's health check (treats < 500 as healthy) waits out HEALTH_DELAY and never
  # flips traffic under HEALTH_FAIL.
  def healthz
    if Harness.ready?
      render json: { status: "ok", uptime_s: Harness.uptime.round(1) }
    else
      render json: { status: "starting", uptime_s: Harness.uptime.round(1) },
             status: :service_unavailable
    end
  end

  # GET /secret — did the env and file secrets arrive? Values are never returned.
  def secret
    render json: Harness.secrets_status
  end

  # GET /counter — increment a counter persisted under DATA_DIR (survives a flip iff the
  # volume does).
  def counter
    render json: Harness.bump_counter
  end
end
