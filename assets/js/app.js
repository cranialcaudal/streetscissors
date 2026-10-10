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
import "./trail"
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

// A tab left open across a deploy is sent the new markup but keeps the old
// stylesheet (WebWeb.FreshAssets). Load the page again, once, and not out
// from under something being typed.
window.addEventListener("phx:stale-assets", () => {
  const typing = document.activeElement?.closest("input:not([type=checkbox]), textarea, [contenteditable]")
  let last = 0
  try { last = Number(sessionStorage.getItem("stale-assets-reload")) } catch (_) {}
  if (typing || Date.now() - last < 60000) return
  try { sessionStorage.setItem("stale-assets-reload", String(Date.now())) } catch (_) {}
  window.location.reload()
})

// "Print this year" on /daybook/:year. That page is a controller render with
// no hooks, so one delegated listener serves any `data-print` button.
document.addEventListener("click", (e) => {
  if (e.target.closest("[data-print]")) window.print()
})

// A page that was fetched ahead of time (the speculation rules in the root
// layout) is not counted as a view by the server, and the browser makes no
// second request when the link is followed. So the page says so itself, once,
// when it is really on screen. Every other page was counted when it was asked for.
const reportSeen = () => {
  const [entry] = performance.getEntriesByType("navigation")
  if (!entry || entry.deliveryType !== "navigational-prefetch") return
  if (!navigator.sendBeacon) return
  navigator.sendBeacon(`/seen?p=${encodeURIComponent(location.pathname)}`)
}
if (document.visibilityState === "visible") reportSeen()
else document.addEventListener("visibilitychange", reportSeen, { once: true })

// The search field offers names as it is typed in. /search is a controller
// render with no hooks, and this is enhancement only: without it the form
// still submits. ↓ ↑ move through the offers, Enter opens the one chosen (or
// searches, if none is), Escape puts them away.
document.addEventListener("DOMContentLoaded", () => {
  const form = document.querySelector("form[data-suggest]")
  const input = form && form.querySelector('input[name="q"]')
  if (!input) return

  const list = document.createElement("ul")
  list.className = "site-search-suggestions"
  list.id = "site-search-suggestions"
  list.setAttribute("role", "listbox")
  list.setAttribute("aria-label", "Suggestions")
  list.hidden = true
  form.appendChild(list)

  input.setAttribute("role", "combobox")
  input.setAttribute("aria-autocomplete", "list")
  input.setAttribute("aria-controls", list.id)
  input.setAttribute("aria-expanded", "false")

  let options = []
  let active = -1
  let timer = null
  let request = null
  let asked = ""

  const choose = (i) => {
    active = i
    options.forEach((option, n) => option.setAttribute("aria-selected", n === i ? "true" : "false"))
    if (i >= 0) input.setAttribute("aria-activedescendant", options[i].id)
    else input.removeAttribute("aria-activedescendant")
  }

  // Put away or brought back, the list starts with nothing chosen.
  const open = (on) => {
    on = on && options.length > 0
    list.hidden = !on
    input.setAttribute("aria-expanded", on ? "true" : "false")
    choose(-1)
  }
  const close = () => open(false)

  // Built with textContent throughout: a title is never parsed as markup.
  const show = (items) => {
    list.replaceChildren()
    options = items.map((item, n) => {
      const row = document.createElement("li")
      row.setAttribute("role", "presentation")
      const link = document.createElement("a")
      link.className = "site-search-suggestion"
      link.id = `site-search-suggestion-${n}`
      link.href = item.path
      link.setAttribute("role", "option")
      link.setAttribute("aria-selected", "false")
      link.tabIndex = -1
      const title = document.createElement("span")
      title.textContent = item.title
      const section = document.createElement("span")
      section.className = "site-search-suggestion-section"
      section.textContent = item.section
      link.append(title, section)
      row.appendChild(link)
      list.appendChild(row)
      return link
    })
    open(true)
  }

  const ask = () => {
    const query = input.value.trim()
    if (query.length < 2) {
      asked = ""
      if (request) request.abort()
      return show([])
    }
    if (query === asked) return open(true)
    asked = query
    if (request) request.abort()
    request = new AbortController()
    // No Accept header of its own: the route sits in the :browser pipeline,
    // which takes html, and answered a request for application/json with 406.
    fetch(`${form.dataset.suggest}?q=${encodeURIComponent(query)}`, { signal: request.signal })
      .then((response) => (response.ok ? response.json() : []))
      // An answer to something no longer in the field is thrown away.
      .then((items) => input.value.trim() === query && show(items))
      .catch(() => {})
  }

  input.addEventListener("input", () => {
    clearTimeout(timer)
    timer = setTimeout(ask, 150)
  })
  input.addEventListener("focus", () => {
    if (input.value.trim() === asked) open(true)
  })

  input.addEventListener("keydown", (e) => {
    if (e.key === "Escape") {
      if (!list.hidden) e.preventDefault()
      return close()
    }
    if (list.hidden || options.length === 0) {
      if (e.key === "ArrowDown") ask()
      return
    }
    if (e.key === "ArrowDown") {
      e.preventDefault()
      choose(active + 1 >= options.length ? 0 : active + 1)
    } else if (e.key === "ArrowUp") {
      e.preventDefault()
      choose(active <= 0 ? options.length - 1 : active - 1)
    } else if (e.key === "Enter" && active >= 0) {
      e.preventDefault()
      location.assign(options[active].href)
    }
  })

  // Pressing an offer must not blur the field first, or the list would
  // close before the click lands.
  list.addEventListener("mousedown", (e) => e.preventDefault())
  document.addEventListener("click", (e) => {
    if (!form.contains(e.target)) close()
  })
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
      if (e.key === "ArrowRight" || (e.key === " " && !e.target.closest("button, a, summary"))) {
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

