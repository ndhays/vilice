// Add an icon "Copy" button to every code block. Static site, no dependencies.
// Accessible: a real <button> with an aria-label, an aria-hidden icon, and a
// shared live region that announces success to screen readers.

const ICON_COPY =
  '<svg viewBox="0 0 16 16" width="15" height="15" fill="none" stroke="currentColor" stroke-width="1.5" aria-hidden="true" focusable="false">' +
  '<rect x="5.5" y="5.5" width="8" height="8" rx="1.5"/>' +
  '<path d="M3.5 10.5H3a1 1 0 0 1-1-1v-7a1 1 0 0 1 1-1h7a1 1 0 0 1 1 1v.5"/></svg>';

const ICON_DONE =
  '<svg viewBox="0 0 16 16" width="15" height="15" fill="none" stroke="currentColor" stroke-width="1.75" aria-hidden="true" focusable="false">' +
  '<path d="M3 8.6l3.3 3.3L13 4.7"/></svg>';

// Copy text to the clipboard. The async Clipboard API only works in a secure
// context (HTTPS or localhost); fall back to a hidden textarea + execCommand so
// copying still works over file:// or a LAN IP.
async function copyText(text) {
  if (navigator.clipboard && window.isSecureContext) {
    await navigator.clipboard.writeText(text);
    return;
  }
  const ta = document.createElement("textarea");
  ta.value = text;
  ta.setAttribute("readonly", "");
  ta.style.position = "fixed";
  ta.style.top = "-9999px";
  document.body.appendChild(ta);
  ta.select();
  const ok = document.execCommand("copy");
  document.body.removeChild(ta);
  if (!ok) throw new Error("execCommand copy failed");
}

document.addEventListener("DOMContentLoaded", () => {
  // One shared live region for announcements.
  const live = document.createElement("div");
  live.className = "visually-hidden";
  live.setAttribute("aria-live", "polite");
  document.body.appendChild(live);

  for (const pre of document.querySelectorAll("main pre")) {
    const wrap = document.createElement("div");
    wrap.className = "code-wrap";
    pre.parentNode.insertBefore(wrap, pre);
    wrap.appendChild(pre);

    const btn = document.createElement("button");
    btn.type = "button";
    btn.className = "copy-btn";
    btn.setAttribute("aria-label", "Copy code");
    btn.title = "Copy";
    btn.innerHTML = ICON_COPY;

    btn.addEventListener("click", async () => {
      const text = (pre.querySelector("code") || pre).innerText;
      try {
        await copyText(text);
        btn.innerHTML = ICON_DONE;
        btn.classList.add("copied");
        btn.setAttribute("aria-label", "Copied");
        live.textContent = "Copied to clipboard";
        setTimeout(() => {
          btn.innerHTML = ICON_COPY;
          btn.classList.remove("copied");
          btn.setAttribute("aria-label", "Copy code");
        }, 1500);
      } catch {
        live.textContent = "Copy failed";
      }
    });

    wrap.appendChild(btn);
  }
});
