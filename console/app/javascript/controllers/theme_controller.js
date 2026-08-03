import { Controller } from "@hotwired/stimulus"

// Flip between light and dark skins and remember the choice. The initial theme
// is applied before paint by a tiny script in the <head>; this just toggles.
export default class extends Controller {
  toggle() {
    const root = document.documentElement
    const current = root.getAttribute("data-theme") ||
      (window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light")
    const next = current === "dark" ? "light" : "dark"
    root.setAttribute("data-theme", next)
    try { localStorage.setItem("theme", next) } catch (e) { /* storage off — session only */ }
  }
}
