import { Controller } from "@hotwired/stimulus"

// The App Library's input editor. Env vars are chips: type a name to add one, click a chip
// to mark it secret (a lock shows), × removes it. Secret files stay as name+path rows.
// Each chip/row carries hidden inputs that apps#app_params rebuilds into the stored lists —
// so the server contract is just the indexed env_rows / secret_file_rows. Names only.
export default class extends Controller {
  static targets = ["envInput", "envChips", "envTemplate", "fileList", "fileTemplate", "toggleText"]

  connect() {
    this.n = Date.now() // unique indices for new chips/rows, distinct from server-rendered
  }

  // The declaration read back is the resting state; editing is the deliberate act. A CSS
  // class swaps which half is visible — the form stays in the DOM either way, so an
  // in-progress edit is not thrown away by toggling, and it submits exactly as before.
  toggle() {
    const editing = this.element.classList.toggle("editing")
    if (this.hasToggleTextTarget) this.toggleTextTarget.textContent = editing ? "Done" : "Edit"
  }

  // Enter (or comma) commits the typed name as a chip; preventDefault stops a form submit.
  keydown(event) {
    if (event.key === "Enter" || event.key === ",") {
      event.preventDefault()
      this.addEnv()
    }
  }

  addEnv() {
    const input = this.envInputTarget
    const name = input.value.trim().replace(/[^A-Za-z0-9_]/g, "") // box-safe env chars only
    if (!name) return
    const html = this.envTemplateTarget.innerHTML
      .replaceAll("NEW", String(this.n++))
      .replaceAll("KEYNAME", name)
    this.envChipsTarget.appendChild(this.node(html))
    input.value = ""
    input.focus()
  }

  toggleSecret(event) {
    const chip = event.currentTarget
    const secret = chip.classList.toggle("is-secret")
    chip.querySelector(".secret-flag").value = secret ? "1" : "0"
  }

  removeChip(event) {
    event.stopPropagation() // don't also toggle the chip we're removing
    event.target.closest(".chip")?.remove()
  }

  addFile() {
    const html = this.fileTemplateTarget.innerHTML.replaceAll("NEW", String(this.n++))
    const row = this.node(html)
    this.fileListTarget.appendChild(row)
    row.querySelector("input")?.focus()
  }

  removeFile(event) {
    event.target.closest(".kv-row")?.remove()
  }

  node(html) {
    const holder = document.createElement("div")
    holder.innerHTML = html.trim()
    return holder.firstElementChild
  }
}
