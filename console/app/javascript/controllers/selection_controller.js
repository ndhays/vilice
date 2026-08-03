import { Controller } from "@hotwired/stimulus"

// Reusable list selection. Wrap a list toolbar + the list itself; this wires a
// master "select all" checkbox, a live count, and bulk-action buttons that stay
// disabled until something is picked. Targets:
//   all    — the master checkbox (toggles every item)
//   item   — a per-row checkbox
//   count  — text that reads the label, or "N selected" once rows are picked
//   action — a bulk button, disabled while nothing is selected
// With no JS the per-row checkboxes still submit; only the select-all convenience
// and the disabled-until-picked guard are lost (the button stays usable).
export default class extends Controller {
  static targets = ["all", "item", "count", "action"]

  connect() {
    // The toolbar's own resting text is the label we restore to when nothing's picked.
    this.label = this.hasCountTarget ? this.countTarget.textContent.trim() : "Select all"
    this.refresh()
  }

  toggleAll() {
    this.itemTargets.forEach((box) => (box.checked = this.allTarget.checked))
    this.refresh()
  }

  toggle() { this.refresh() }

  refresh() {
    const items = this.itemTargets
    const picked = items.filter((box) => box.checked).length

    if (this.hasAllTarget) {
      this.allTarget.checked = picked > 0 && picked === items.length
      this.allTarget.indeterminate = picked > 0 && picked < items.length
    }
    if (this.hasCountTarget) {
      this.countTarget.textContent = picked > 0 ? `${picked} selected` : this.label
    }
    this.actionTargets.forEach((btn) => (btn.disabled = picked === 0))
  }
}
