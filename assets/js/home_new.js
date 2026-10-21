// The homepage's corner card (#home-new): the newest post, video and roll,
// sliding in over the tiles a moment after the page loads. It is not a
// dialog: it takes no focus and blocks nothing. Closing it (× or Escape)
// keeps it closed until what it shows changes (data-new, from the server),
// so a reader sees each new thing once rather than on every visit.

const KEY = "home-new-closed"
const DELAY_MS = 1200

export const initHomeNew = () => {
  const card = document.getElementById("home-new")
  if (!card) return
  const shows = card.dataset.new || ""

  let closed = null
  try { closed = localStorage.getItem(KEY) } catch (_) {}
  if (closed !== null && closed === shows) return

  const close = () => {
    card.classList.remove("is-open")
    try { localStorage.setItem(KEY, shows) } catch (_) {}
    // After the slide out; at once when there is no transition to wait for.
    const done = () => { card.hidden = true }
    if (getComputedStyle(card).transitionDuration === "0s") done()
    else card.addEventListener("transitionend", done, { once: true })
  }

  const button = card.querySelector("[data-new-close]")
  if (button) button.addEventListener("click", close)
  card.addEventListener("keydown", (e) => { if (e.key === "Escape") close() })

  setTimeout(() => {
    card.hidden = false
    // One frame hidden-to-shown first, so the slide in has somewhere to start.
    requestAnimationFrame(() => requestAnimationFrame(() => card.classList.add("is-open")))
  }, DELAY_MS)
}
