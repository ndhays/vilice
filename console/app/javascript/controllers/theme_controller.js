import { Controller } from "@hotwired/stimulus"

// The rail's light/dark toggle. Appearance is stored on the user, so flipping it
// is a form post — but the operator shouldn't wait a round trip to see it, so the
// mode is swapped on the element first and then persisted.
//
// Only the browser knows the *resolved* mode when the stored preference is
// `system` (the pre-paint script in the layout resolved it), so the opposite is
// computed from the element rather than from anything the server sent. Picking
// `system` back is done in Settings, where the three-way choice belongs.
export default class extends Controller {
  static targets = ["mode"]

  toggle(event) {
    const root = document.documentElement
    const next = root.getAttribute("data-mode") === "dark" ? "light" : "dark"
    root.setAttribute("data-mode", next)
    this.modeTarget.value = next
    // Let the form submit carry the change to the user record.
  }
}
