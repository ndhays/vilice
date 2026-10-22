import { Controller } from "@hotwired/stimulus"

// Says an act has been sent. An act blocks until the box answers, which can be most of
// a minute for a deploy, and until then the page showed nothing. On submit the pressed
// button goes inert and its label becomes `data-busy-text-value`.
//
// The button is disabled a tick later, not in the submit event: a disabled button is
// left out of the form's data, and the confirm button's own name is what makes the
// request an act. With no JS the form still submits — it just says nothing.
export default class extends Controller {
  static values = { text: { type: String, default: "running…" } }

  start(event) {
    const button = event.submitter
    if (!button || button.dataset.busy === "false") return

    setTimeout(() => {
      button.disabled = true
      button.setAttribute("aria-busy", "true")
      const label = button.querySelector(".cmd-verb") || button
      label.textContent = `${label.textContent.trim()} · ${this.textValue}`
    }, 0)
  }
}
