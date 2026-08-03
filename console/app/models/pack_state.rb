# A read-only view over one `steward packs --json` reply: what code the box says may
# run on it. There is no table behind this — the manifest is the box's fact, and a
# stored copy would be a second answer that could quietly disagree.
#
# It exists so the machine view can be *pack-shaped*: sections appear because the box
# reports the pack, not because the console assumed which packs a box has.
class PackState
  ACTIVE = "active".freeze

  attr_reader :result

  def initialize(result) = @result = result || {}

  def reachable? = result[:ok].present?

  def error = result[:error].presence || "could not read the manifest"

  def all
    return [] unless reachable?
    Array(result.dig(:data, "data", "packs"))
  end

  # The packs actually running. Only these may drive UI — a stale or unauthorized
  # pack's verbs are refused at the gate, so offering its buttons would be a lie.
  def active = all.select { |p| p["state"] == ACTIVE }

  def problems = all.reject { |p| p["state"] == ACTIVE }

  def active?(name) = active.any? { |p| p["name"] == name }

  # Does this box run the app pack? The machine view's Apps section hangs off this.
  def apps? = active?("steward-app")

  def manifest_path = result.dig(:data, "data", "manifest")
end
