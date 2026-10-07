// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import { hooks as colocatedHooks } from "phoenix-colocated/web"
import topbar from "../vendor/topbar"
import { GymRoutine } from "./gym_routine"
import { MarkdownEditor } from "./markdown_editor"
import { PcTerminal, AutoScroll } from "./pc_terminal"
import { initEmissionsControls } from "./emissions_controls"

document.addEventListener("DOMContentLoaded", () => initEmissionsControls())
window.addEventListener("phx:page-loading-stop", () => initEmissionsControls())

const DispatchOverlay = {
  mounted() {
    window.addEventListener("trigger-dispatch", _ => {
      this.pushEvent("open_dispatch", {})
    })
  }
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: { _csrf_token: csrfToken },
  hooks: { ...colocatedHooks, GymRoutine, MarkdownEditor, PcTerminal, AutoScroll, DispatchOverlay },
})

// Show progress bar on live navigation and form submits
topbar.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" })
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

window.addEventListener("phx:copy_to_clipboard", (e) => {
  if (navigator.clipboard) {
    navigator.clipboard.writeText(e.detail.text).then(() => {
      // Optional: replace with a nicer toast if available
      console.log("Copied to clipboard");
    });
  }
})

// "Print this year" on /almanac/:year. That page is a controller render with
// no hooks, so one delegated listener serves any `data-print` button.
document.addEventListener("click", (e) => {
  if (e.target.closest("[data-print]")) window.print()
})

// The prayer pages (/Christ/*) are controller renders with no hooks, and all of
// this is enhancement: without it every prayer still opens (they are
// <details>), the Rosary is written out in full, and the day links work.
// Nothing here stores anything.
document.addEventListener("DOMContentLoaded", () => {
  const typing = (e) => e.target.closest("input, textarea, select, [contenteditable]")
  const plain = (e) => !(e.metaKey || e.ctrlKey || e.altKey || e.shiftKey)

  // The day's prayer: mark the one it is time for by the reader's own clock
  // (the server only knows Pacific time; `until` runs past 24 for Night
  // Prayer) and, when the page is showing today, open it.
  const hours = document.querySelector("[data-prayer-day]")
  if (hours) {
    const rows = [...hours.querySelectorAll("details[data-prayer-from]")]
    if (hours.dataset.prayerDay === "today") {
      const hour = new Date().getHours()
      rows.forEach((row) => {
        const from = Number(row.dataset.prayerFrom)
        const until = Number(row.dataset.prayerUntil)
        if ((hour >= from && hour < until) || hour + 24 < until) {
          row.classList.add("is-now")
          if (!location.hash) row.open = true
        }
      })
    }

    // A link to one prayer (/Christ#vespers) opens it.
    const linked = location.hash && hours.querySelector(`details#${CSS.escape(location.hash.slice(1))}`)
    if (linked) linked.open = true

    const toggle = hours.querySelector("[data-prayer-toggle]")
    if (toggle) {
      const label = () => (toggle.textContent = rows.every((r) => r.open) ? "Close all" : "Open all")
      toggle.hidden = false
      toggle.addEventListener("click", () => {
        const open = !rows.every((r) => r.open)
        rows.forEach((r) => (r.open = open))
        label()
      })
      rows.forEach((r) => r.addEventListener("toggle", label))
      label()
    }
  }

  // The Rosary, bead by bead.
  const rosary = document.querySelector("[data-rosary]")
  let stepping = false
  if (rosary) {
    const steps = [...rosary.querySelectorAll("li[data-bead]")]
    const track = rosary.querySelector("[data-rosary-track]")
    const count = rosary.querySelector("[data-rosary-count]")
    const back = rosary.querySelector("[data-rosary-back]")
    const next = rosary.querySelector("[data-rosary-next]")
    const mode = document.querySelector("[data-rosary-mode]")
    const text = document.querySelector("[data-rosary-text]")
    const beads = steps.map((step) => {
      const bead = document.createElement("span")
      bead.className = `faith-bead faith-bead--${step.dataset.bead}`
      track.appendChild(bead)
      return bead
    })
    let at = 0

    const show = (i) => {
      at = Math.max(0, Math.min(steps.length - 1, i))
      steps.forEach((step, n) => (step.hidden = n !== at))
      beads.forEach((bead, n) => {
        bead.classList.toggle("is-done", n < at)
        bead.classList.toggle("is-current", n === at)
      })
      count.textContent = `${at + 1} of ${steps.length}`
      back.disabled = at === 0
      next.disabled = at === steps.length - 1
    }

    const setMode = (on) => {
      stepping = on
      rosary.hidden = !on
      text.hidden = on
      mode.textContent = on ? "Show the whole text" : "Pray bead by bead"
      if (on) show(at)
    }

    back.addEventListener("click", () => show(at - 1))
    next.addEventListener("click", () => show(at + 1))
    mode.addEventListener("click", () => setMode(!stepping))
    mode.hidden = false

    document.addEventListener("keydown", (e) => {
      if (!stepping || typing(e) || !plain(e)) return
      if (e.key === "ArrowRight" || (e.key === " " && !e.target.closest("button, a"))) {
        e.preventDefault()
        show(at + 1)
      } else if (e.key === "ArrowLeft") {
        e.preventDefault()
        show(at - 1)
      }
    })
  }

  // ← and → turn to the previous and next day, month or chapter.
  if (document.querySelector(".faith-turn")) {
    document.addEventListener("keydown", (e) => {
      if (stepping || typing(e) || !plain(e)) return
      const rel = { ArrowLeft: "prev", ArrowRight: "next" }[e.key]
      const link = rel && document.querySelector(`.faith-turn a[rel="${rel}"]`)
      if (link) location.assign(link.href)
    })
  }
})

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({ detail: reloader }) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if (keyDown === "c") {
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if (keyDown === "d") {
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

// Register Service Worker for PWA / offline support
if (
  "serviceWorker" in navigator &&
  (window.location.protocol === "https:" ||
    window.location.hostname === "localhost" ||
    window.location.hostname === "127.0.0.1")
) {
  window.addEventListener("load", () => {
    navigator.serviceWorker
      .register("/sw.js")
      .then((reg) => {
        reg.addEventListener("updatefound", () => {
          const newWorker = reg.installing
          if (newWorker) {
            newWorker.addEventListener("statechange", () => {
              if (newWorker.state === "installed" && navigator.serviceWorker.controller) {
                console.log("[PWA] New content ready.")
              }
            })
          }
        })
      })
      .catch((err) => console.debug("[PWA] SW register skipped:", err))
  })
}

