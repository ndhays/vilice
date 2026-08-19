import { Controller } from "@hotwired/stimulus"

// The App Library's input editor. Env vars are chips: type a name to add one, click a chip
// to mark it secret (a lock shows), × removes it. Secret files stay as name+path rows.
// Each chip/row carries hidden inputs that apps#app_params rebuilds into the stored lists —
// so the server contract is just the indexed env_rows / secret_file_rows. Names only.
export default class extends Controller {
  static targets = ["envInput", "envChips", "envTemplate", "fileList", "fileTemplate",
                    "accessoryList", "accessoryTemplate", "toggleText", "form"]

  connect() {
    this.n = Date.now() // unique indices for new chips/rows, distinct from server-rendered
    // The form as the server rendered it — what Cancel restores. Saving reloads the
    // page, so this never goes stale.
    if (this.hasFormTarget) this.pristine = this.formTarget.innerHTML
    this.dirty = false
  }

  // The declaration read back is the resting state; editing is the deliberate act.
  //
  // Closing matters more than it looks. Nothing here is saved until "Save Inputs" is
  // pressed, so closing an editor with unsaved edits *discards* them — and the label
  // has to say so. It read "Done", which claims the opposite, and the read-back
  // underneath would then show the saved state, making it look as though the edits
  // had landed. Untouched, the button is "Done" and closing is harmless; changed, it
  // is "Cancel" and closing puts the form back the way the server sent it.
  toggle() {
    if (this.element.classList.contains("editing") && this.dirty) this.discard()
    const editing = this.element.classList.toggle("editing")
    this.relabel(editing)
  }

  // Any edit at all — typing, adding, removing, flipping a secret flag.
  touch() {
    if (this.dirty) return
    this.dirty = true
    this.relabel(true)
  }

  discard() {
    if (this.hasFormTarget && this.pristine !== undefined) this.formTarget.innerHTML = this.pristine
    this.dirty = false
  }

  relabel(editing) {
    if (!this.hasToggleTextTarget) return
    this.toggleTextTarget.textContent = editing ? (this.dirty ? "Cancel" : "Done") : "Edit"
    this.element.classList.toggle("is-dirty", editing && this.dirty)
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
    this.touch()
  }

  toggleSecret(event) {
    const chip = event.currentTarget
    const secret = chip.classList.toggle("is-secret")
    chip.querySelector(".secret-flag").value = secret ? "1" : "0"
    this.touch()
  }

  removeChip(event) {
    event.stopPropagation() // don't also toggle the chip we're removing
    event.target.closest(".chip")?.remove()
    this.touch()
  }

  addFile() {
    const html = this.fileTemplateTarget.innerHTML.replaceAll("NEW", String(this.n++))
    const row = this.node(html)
    this.fileListTarget.appendChild(row)
    row.querySelector("input")?.focus()
    this.touch()
  }

  removeFile(event) {
    event.target.closest(".kv-row")?.remove()
    this.touch()
  }

  // Accessories — same shape as the file rows, a wider row. `removeRow` walks to
  // whichever kind of row it is in, so one handler serves both.
  addAccessory() {
    const html = this.accessoryTemplateTarget.innerHTML.replaceAll("NEW", String(this.n++))
    const row = this.node(html)
    this.accessoryListTarget.appendChild(row)
    row.querySelector("input")?.focus()
    this.touch()
  }

  removeRow(event) {
    event.target.closest(".acc-row, .kv-row")?.remove()
    this.touch()
  }

  node(html) {
    const holder = document.createElement("div")
    holder.innerHTML = html.trim()
    return holder.firstElementChild
  }
}
