// The England trip's two unlisted pages (/england2026 and its call page). They
// are controller renders with no hooks, so each part starts from its own
// element when the page has it, and does nothing anywhere else.

// /england2026: tabs (buttons carry data-tab), a calendar day jumps to that
// day of the itinerary (data-jump-day), and the packing list remembers its
// ticks in this browser.
const showTab = (tabId) => {
  document.querySelectorAll(".england-container .tab-content").forEach((tab) => {
    tab.classList.toggle("active", tab.id === tabId)
  })
  document.querySelectorAll(".england-container .tab-btn").forEach((btn) => {
    const on = btn.dataset.tab === tabId
    btn.classList.toggle("active", on)
    btn.setAttribute("aria-selected", on ? "true" : "false")
  })
}

const initTrip = (root) => {
  root.addEventListener("click", (e) => {
    const tab = e.target.closest("[data-tab]")
    if (tab) return showTab(tab.dataset.tab)

    const day = e.target.closest("[data-jump-day]")
    if (day) {
      showTab("itinerary")
      const target = document.getElementById("day-" + day.dataset.jumpDay)
      if (target) target.scrollIntoView({ behavior: "smooth", block: "start" })
    }
  })

  // Tag each "Day N" heading in the rendered brief so calendar cells can link to it.
  root.querySelectorAll("#itinerary h2").forEach((h, i) => {
    h.id = "day-" + (i + 1)
  })

  const checklist = root.querySelector("#checklist")
  if (!checklist) return
  const STORAGE_KEY = "england_checklist_state"
  const read = () => {
    try { return JSON.parse(localStorage.getItem(STORAGE_KEY) || "{}") } catch (_) { return {} }
  }
  const write = (state) => {
    try { localStorage.setItem(STORAGE_KEY, JSON.stringify(state)) } catch (_) {}
  }

  // Key saved state by section + item text, not index, so list edits don't
  // shift ticks and duplicate items ("Inner tube" x2) don't collide.
  const keyFor = (cb) => {
    const li = cb.closest("li")
    const section = li?.closest("ul")?.previousElementSibling?.textContent?.trim().slice(0, 40) || ""
    return section + "::" + (li?.textContent || "").trim().slice(0, 80)
  }

  const saved = read()
  checklist.querySelectorAll('input[type="checkbox"]').forEach((cb) => {
    if (saved[keyFor(cb)]) cb.checked = true

    cb.addEventListener("change", () => {
      const state = read()
      state[keyFor(cb)] = cb.checked
      write(state)
    })

    // Whole row toggles — the checkbox alone is a fiddly tap target on phones.
    cb.closest("li")?.addEventListener("click", (e) => {
      if (e.target === cb) return
      cb.checked = !cb.checked
      cb.dispatchEvent(new Event("change"))
    })
  })
}

// /england2026/call: both clocks, and whether it is a good time to call. The
// window, the time zones and the banner's words are data attributes on
// #call-now, from the trip's content.
const initCall = (banner) => {
  const cfg = banner.dataset

  const update = () => {
    const now = new Date()
    const fmt = (tz) =>
      new Intl.DateTimeFormat("en-US", {
        timeZone: tz, weekday: "short", hour: "numeric", minute: "2-digit"
      }).format(now)
    document.getElementById("clock-ca").textContent = fmt(cfg.homeTz)
    document.getElementById("clock-uk").textContent = fmt(cfg.awayTz)

    const parts = new Intl.DateTimeFormat("en-CA", {
      timeZone: cfg.homeTz, hour: "2-digit", minute: "2-digit", hour12: false
    }).formatToParts(now)
    const get = (t) => parseInt(parts.find((p) => p.type === t).value, 10)
    const hour = (get("hour") % 24) + get("minute") / 60

    const good = hour >= Number(cfg.windowStart) && hour < Number(cfg.windowEnd)
    banner.textContent = good ? cfg.good : cfg.wait
    banner.className = "now-banner " + (good ? "good" : "wait")
  }

  update()
  setInterval(update, 30000)
}

export const initEngland = () => {
  const trip = document.querySelector(".england-container")
  if (trip) initTrip(trip)
  const banner = document.getElementById("call-now")
  if (banner) initCall(banner)
}
