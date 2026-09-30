import { Controller } from "@hotwired/stimulus"

// Drives the install form's progressive reveal. Choosing an app fills the version picker
// and the app's defaults, then reveals the rest of the form; "Custom image" hides the
// version (custom is custom — no app/version tracking). Degrades gracefully: with no JS,
// every section is simply visible from the start.
export default class extends Controller {
  static targets = [
    "rest", "version", "versionField", "imageField", "search",
    "name", "port", "health"
  ]

  connect() {
    // Only hide things once JS is here to reveal them again.
    this.restTarget.hidden = true
    this.versionFieldTarget.hidden = true
    if (this.hasImageFieldTarget) this.imageFieldTarget.hidden = true

    const chosen = this.element.querySelector('input[name="install[app_template_id]"]:checked')
    if (chosen) this.pick(chosen)
  }

  pickApp(event) {
    this.pick(event.target)
  }

  pick(radio) {
    const custom = radio.dataset.custom === "true"
    this.restTarget.hidden = false
    this.versionFieldTarget.hidden = custom
    if (this.hasImageFieldTarget) {
      this.imageFieldTarget.hidden = !custom
      if (!custom) this.clearImage()
    }

    if (custom) {
      this.versionTarget.innerHTML = ""  // no app/version for a custom image
      return
    }

    this.fillVersions(JSON.parse(radio.dataset.versions || "[]"))
    this.setField(this.nameTarget, radio.dataset.name)
    this.setField(this.portTarget, radio.dataset.port)
    this.setField(this.healthTarget, radio.dataset.health)
  }

  // Filter the catalog rows by app name as the operator types.
  filter() {
    const q = this.searchTarget.value.trim().toLowerCase()
    this.element.querySelectorAll(".pick-list .pick-option").forEach((opt) => {
      const name = (opt.querySelector('input[name="install[app_template_id]"]')?.dataset.name || "").toLowerCase()
      opt.hidden = q.length > 0 && !name.includes(q)
    })
  }

  fillVersions(versions) {
    this.versionTarget.innerHTML = ""
    versions.forEach((v) => {
      const opt = document.createElement("option")
      opt.value = v.id
      opt.textContent = v.latest ? `${v.tag} (latest)` : v.tag
      if (v.latest) opt.selected = true
      this.versionTarget.appendChild(opt)
    })
  }

  setField(field, value) {
    if (field) field.value = value || ""
  }

  clearImage() {
    const input = this.imageFieldTarget.querySelector("input")
    if (input) input.value = ""
  }
}
