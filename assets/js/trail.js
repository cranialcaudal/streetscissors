// The header's Back goes to the last *thing* the reader was looking at.
//
// The link in the markup (CoreComponents.blog_header/1, marked `data-back`)
// points at the page's parent: an exercise goes back to the wiki's index, a
// post to the blog. That is right for someone who arrived from outside, and
// wrong for someone browsing: from Tuesday's checklist to an exercise and
// Back should be Tuesday, and from a post to a photograph and Back should be
// the post. The browser's own Back is not it either: stepping through nine
// rolls of negatives and pressing Back should leave the archive, not show
// roll eight.
//
// So this keeps a trail of things, per tab (sessionStorage), nothing sent
// anywhere:
//
//   * a *thing* is a page's path, without its query (a sort, a filter, an
//     overlay opened over it are the same thing);
//   * some sections are one thing however far the reader walks inside them
//     (FAMILIES): the negatives archive, the days of the regimen, the
//     daybook's weeks. The trail remembers the last address seen there, so
//     Back returns to the roll or the day that was open, not the front door;
//   * arriving on the thing just before the newest one is going back, by
//     this button or the browser's, and takes the newest off the trail.
//
// Back then goes to the thing before this one, and says so; with no trail
// (a first page, a link from elsewhere) the link is left as the server
// wrote it. The admin keeps its own navigation and is not followed.
//
// What the site is made of makes this possible: every piece has one address
// of its own (a post, a log, a roll, a frame, an exercise, a day), and every
// view of it is in that address's query, so "the same thing" can be read
// off the path alone.

const KEY = "trail"
const MOST = 40

// [prefix, the thing every path under it counts as]
const FAMILIES = [
  ["/negatives", "/negatives"],
  ["/archive", "/negatives"],
  ["/fitness/day", "/fitness"],
  ["/daybook", "/daybook"],
]

const thing = (path) => {
  const clean = path.replace(/\/+$/, "") || "/"
  for (const [prefix, as] of FAMILIES) {
    if (clean === prefix || clean.startsWith(prefix + "/")) return as
  }
  return clean
}

const read = () => {
  try {
    const trail = JSON.parse(sessionStorage.getItem(KEY) || "[]")
    return Array.isArray(trail) ? trail : []
  } catch (_) {
    return []
  }
}

const write = (trail) => {
  try { sessionStorage.setItem(KEY, JSON.stringify(trail.slice(-MOST))) } catch (_) {}
}

const title = () => (document.querySelector("h1.theme-title, main h1, article h1")?.textContent || document.title || "").trim().replace(/\s+/g, " ")

// Called whenever a page is shown, however it was reached.
const arrive = () => {
  if (location.pathname.startsWith("/admin")) return
  const here = { thing: thing(location.pathname), url: location.pathname + location.search, title: title() }
  const trail = read()
  const top = trail[trail.length - 1]

  if (top && top.thing === here.thing) trail[trail.length - 1] = here
  else if (trail.length > 1 && trail[trail.length - 2].thing === here.thing) { trail.pop(); trail[trail.length - 1] = here }
  else trail.push(here)

  write(trail)
  label(trail)
}

const short = (text) => (text.length > 22 ? text.slice(0, 21).trimEnd() + "…" : text)

// The control says where it goes.
const label = (trail) => {
  const link = document.querySelector("a[data-back]")
  const before = trail[trail.length - 2]
  if (!link || !before || !before.title) return
  const text = link.querySelector(".header-action-label")
  if (text) text.textContent = short(before.title)
  link.setAttribute("aria-label", `Back to ${before.title}`)
}

document.addEventListener("click", (event) => {
  const link = event.target.closest?.("a[data-back]")
  if (!link || event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return
  const trail = read()
  const before = trail[trail.length - 2]
  if (!before || location.pathname.startsWith("/admin")) return
  event.preventDefault()
  window.location.assign(before.url)
})

if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", arrive)
else arrive()
// LiveView moves between pages without loading one: every navigation and
// patch ends here.
window.addEventListener("phx:page-loading-stop", arrive)
// A page restored from the back/forward cache runs no script.
window.addEventListener("pageshow", (event) => { if (event.persisted) arrive() })
