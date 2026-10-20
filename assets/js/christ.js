// The prayer pages (/Christ/*), moved out of app.js. They are controller
// renders with no hooks, and all of this is enhancement: without it every
// prayer still opens (they are <details>), the Rosary is written out in
// full, and the day links work. Nothing here stores anything. Each part
// starts from its own element, so on any other page this does nothing.
export const initChrist = () => {
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
      bead.className = `christ-bead christ-bead--${step.dataset.bead}`
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
  if (document.querySelector(".christ-turn")) {
    document.addEventListener("keydown", (e) => {
      if (stepping || typing(e) || !plain(e)) return
      const rel = { ArrowLeft: "prev", ArrowRight: "next" }[e.key]
      const link = rel && document.querySelector(`.christ-turn a[rel="${rel}"]`)
      if (link) location.assign(link.href)
    })
  }
}
