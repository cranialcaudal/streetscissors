// The homepage's newest captain's log plays a few silent seconds in the corner
// card (#home-new):
// on hover with a mouse, or while it is on screen on a phone. Enhancement
// only: the card is a link with a poster, and nothing here runs, or fetches
// a byte of video, until the reader points at it or scrolls to it.
//
// Items opt in with data-preview="<video address>" (home.html.heex). Never
// under prefers-reduced-motion or a Save-Data connection.

const PREVIEW_SECONDS = 8

const allowed = () => {
  if (window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches) return false
  const connection = navigator.connection
  return !(connection && connection.saveData)
}

// One video per card, made on first use and kept (paused) after.
const videoFor = (card) => {
  if (card._preview) return card._preview
  const plate = card.querySelector(".new-plate")
  if (!plate) return null
  const video = document.createElement("video")
  video.muted = true
  video.defaultMuted = true
  video.playsInline = true
  video.loop = true
  video.preload = "metadata"
  video.setAttribute("aria-hidden", "true")
  video.setAttribute("tabindex", "-1")
  video.src = card.dataset.preview
  // A preview is the opening seconds, not the whole log.
  video.addEventListener("timeupdate", () => {
    if (video.currentTime > PREVIEW_SECONDS) video.currentTime = 0
  })
  plate.appendChild(video)
  card._preview = video
  return video
}

const play = (card) => {
  const video = videoFor(card)
  if (!video) return
  const started = video.play()
  card.classList.add("is-playing")
  // A browser that refuses (no autoplay, a bad file) leaves the poster.
  if (started && started.catch) started.catch(() => stop(card))
}

const stop = (card) => {
  card.classList.remove("is-playing")
  if (card._preview) card._preview.pause()
}

export const initHomePreviews = () => {
  const cards = [...document.querySelectorAll("[data-preview]")].filter((c) => c.dataset.preview)
  if (cards.length === 0 || !allowed()) return

  const hover = window.matchMedia && window.matchMedia("(hover: hover) and (pointer: fine)").matches

  if (hover) {
    for (const card of cards) {
      card.addEventListener("pointerenter", () => play(card))
      card.addEventListener("pointerleave", () => stop(card))
      card.addEventListener("focus", () => play(card))
      card.addEventListener("blur", () => stop(card))
    }
    return
  }

  // Touch: while most of the card is on screen, one at a time.
  if (!("IntersectionObserver" in window)) return
  let current = null
  const watch = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      if (entry.isIntersecting && entry.intersectionRatio >= 0.6) {
        if (current && current !== entry.target) stop(current)
        current = entry.target
        play(entry.target)
      } else if (current === entry.target) {
        stop(entry.target)
        current = null
      }
    }
  }, { threshold: [0, 0.6, 1] })
  cards.forEach((card) => watch.observe(card))
}
