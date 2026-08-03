import { Controller } from "@hotwired/stimulus"

// Click-to-copy. Copies `data-clipboard-text-value` to the clipboard and briefly
// flips the button to a check (the `copied` class swaps the icon, see CSS). Reusable
// on anything with a long value to grab. Degrades to nothing with no JS — the value
// is still in the DOM and selectable.
export default class extends Controller {
  static values = { text: String }

  copy() {
    // navigator.clipboard exists only in a secure context (https or localhost). Over
    // plain http to a LAN host it's undefined, so fall back to the legacy path.
    if (navigator.clipboard && window.isSecureContext) {
      navigator.clipboard.writeText(this.textValue).then(() => this.flash()).catch(() => this.legacyCopy())
    } else {
      this.legacyCopy()
    }
  }

  legacyCopy() {
    const field = document.createElement("textarea")
    field.value = this.textValue
    field.setAttribute("readonly", "")
    field.style.position = "fixed"
    field.style.left = "-9999px"
    document.body.appendChild(field)
    field.select()
    try { document.execCommand("copy"); this.flash() } catch (_) { /* clipboard blocked */ }
    document.body.removeChild(field)
  }

  flash() {
    this.element.classList.add("copied")
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.element.classList.remove("copied"), 1200)
  }
}
