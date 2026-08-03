import { Controller } from "@hotwired/stimulus"

// Toggle a labels block between read and edit mode — same labels, just reveals
// the per-label remove and the add form, and flips Edit <-> Done.
export default class extends Controller {
  static targets = ["toggleText"]

  toggle() {
    const editing = this.element.classList.toggle("editing")
    if (this.hasToggleTextTarget) this.toggleTextTarget.textContent = editing ? "Done" : "Edit"
  }
}
