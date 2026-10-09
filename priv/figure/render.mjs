// Films figure tracks: drives headless Chrome through the renderer page and
// pipes each frame to ffmpeg. No dependencies beyond node, Chrome and ffmpeg.
//
//   node render.mjs <jobs.json> <out dir> [--stills]
//
// jobs.json is [{slug, track, muscles}] (Web.Fitness.Clip writes it). For each
// it writes <slug>.mp4 and <slug>.jpg (the first frame), and prints a line of
// JSON saying what it made. With --stills it writes a PNG of each pose
// instead, which is how a figure is looked at before it is filmed.
//
// CHROME_BIN and FFMPEG_BIN name the two programs when they are not on PATH.
import { spawn } from "node:child_process"
import { createServer } from "node:http"
import { readFileSync, writeFileSync, mkdtempSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { dirname, join, extname } from "node:path"
import { fileURLToPath } from "node:url"

const here = dirname(fileURLToPath(import.meta.url))
const [jobsPath, outDir, ...flags] = process.argv.slice(2)
if (!jobsPath || !outDir) {
  console.error("usage: node render.mjs <jobs.json> <out dir> [--stills]")
  process.exit(2)
}
const stills = flags.includes("--stills")
const jobs = JSON.parse(readFileSync(jobsPath, "utf8"))
const HEIGHT = 1080 // drawn at one and a half times the size it is kept at, which is its antialiasing
const chrome = process.env.CHROME_BIN || "google-chrome"
const ffmpeg = process.env.FFMPEG_BIN || "ffmpeg"

// The page imports figure3d.js as a module, which a file:// page may not.
const pages = { "/": "render.html", "/render.html": "render.html", "/figure3d.js": "figure3d.js" }
const server = createServer((req, res) => {
  const name = pages[req.url.split("?")[0]]
  if (!name) { res.writeHead(404); res.end(); return }
  const type = { ".html": "text/html", ".js": "text/javascript" }[extname(name)]
  res.writeHead(200, { "content-type": type }); res.end(readFileSync(join(here, name)))
})
await new Promise((ok) => server.listen(0, "127.0.0.1", ok))
const port = server.address().port

const profile = mkdtempSync(join(tmpdir(), "figure-film-"))
// gl-egl is the machine's own GPU; without it Chrome marches the rays on the CPU.
const browser = spawn(chrome, ["--headless=new", "--no-sandbox", "--use-angle=gl-egl", "--hide-scrollbars",
  "--remote-debugging-port=0", `--user-data-dir=${profile}`, "about:blank"], { stdio: ["ignore", "ignore", "pipe"] })

// The browser is given time to go before its profile is removed from under
// it, or the profile (up to 200 MB of shader cache) is left in the temp folder.
const close = async () => {
  server.close()
  if (browser.exitCode === null && browser.signalCode === null) {
    const gone = new Promise((ok) => browser.once("exit", ok))
    browser.kill()
    await Promise.race([gone, new Promise((ok) => setTimeout(ok, 3000))])
  }
  // its helper processes write for a moment after it has gone
  await new Promise((ok) => setTimeout(ok, 300))
  try { rmSync(profile, { recursive: true, force: true, maxRetries: 10, retryDelay: 200 }) } catch {}
}

// Stopped from outside (the task was interrupted): take the browser along.
for (const signal of ["SIGINT", "SIGTERM", "SIGHUP"]) {
  process.once(signal, async () => { await close(); process.exit(1) })
}

const piped = (args, feed) => new Promise((ok, no) => {
  const ff = spawn(ffmpeg, ["-y", "-loglevel", "error", ...args], { stdio: ["pipe", "inherit", "inherit"] })
  ff.on("error", no)
  ff.on("exit", (code) => (code === 0 ? ok() : no(new Error(`ffmpeg exited ${code}`))))
  feed(ff.stdin).then(() => ff.stdin.end(), no)
})

try {
  const wsUrl = await new Promise((ok, no) => {
    let err = ""
    browser.stderr.on("data", (d) => { err += d; const m = err.match(/DevTools listening on (ws:\/\/\S+)/); if (m) ok(m[1]) })
    browser.on("error", (e) => no(new Error(`could not run ${chrome}: ${e.message}`)))
    browser.on("exit", () => no(new Error("the browser did not start:\n" + err)))
  })

  const ws = new WebSocket(wsUrl)
  await new Promise((ok, no) => { ws.onopen = ok; ws.onerror = () => no(new Error("no answer from the browser")) })
  let seq = 0; const waiting = new Map()
  ws.onmessage = (e) => { const m = JSON.parse(e.data); if (m.id && waiting.has(m.id)) { waiting.get(m.id)(m); waiting.delete(m.id) } }
  const send = (method, params = {}, sessionId) => new Promise((ok, no) => {
    const id = ++seq
    waiting.set(id, (m) => (m.error ? no(new Error(method + ": " + m.error.message)) : ok(m.result)))
    ws.send(JSON.stringify({ id, method, params, sessionId }))
  })
  const { targetId } = await send("Target.createTarget", { url: `http://127.0.0.1:${port}/render.html` })
  const { sessionId } = await send("Target.attachToTarget", { targetId, flatten: true })
  const run = async (expression) => {
    const r = await send("Runtime.evaluate", { expression, returnByValue: true, awaitPromise: true }, sessionId)
    if (r.exceptionDetails) throw new Error(r.exceptionDetails.exception?.description || r.exceptionDetails.text)
    return r.result.value
  }
  let ready = false
  for (let i = 0; i < 100 && !ready; i++) {
    ready = await run("window.F3D && window.F3D.ready === true")
    if (!ready) await new Promise((ok) => setTimeout(ok, 100))
  }
  if (!ready) throw new Error("the renderer page did not load")

  const png = async (i) => Buffer.from((await run(`F3D.png(${i})`)).split(",")[1], "base64")

  for (const job of jobs) {
    const started = Date.now()
    const info = await run(`F3D.load(${JSON.stringify(job.track)}, ${JSON.stringify(job.muscles)}, ${HEIGHT})`)
    if (stills) {
      const count = info.frames
      const at = job.track.stops.map((s) => Math.min(Math.round((s.at / job.track.seconds) * count), count - 1))
      for (const [n, i] of at.entries()) writeFileSync(join(outDir, `${job.slug}-${n}.png`), await png(i))
      console.log(JSON.stringify({ slug: job.slug, stills: at.length, ms: Date.now() - started }))
      continue
    }
    const out = join(outDir, job.slug)
    // Kept at two thirds of what was drawn, with even sides, as H.264 wants.
    const scale = "scale=trunc(iw/3)*2:trunc(ih/3)*2:flags=lanczos" + (job.track.mirror ? ",hflip" : "")
    let first = null
    // A keyframe every two seconds, so a pose's button lands on it at once.
    await piped(["-f", "image2pipe", "-framerate", String(job.track.fps), "-c:v", "png", "-i", "-",
      "-vf", scale, "-c:v", "libx264", "-preset", "slow", "-crf", "25", "-g", String(job.track.fps * 2),
      "-pix_fmt", "yuv420p", "-movflags", "+faststart", "-an", out + ".mp4"], async (stdin) => {
      for (let i = 0; i < info.frames; i++) {
        const frame = await png(i)
        first ??= frame
        if (!stdin.write(frame)) await new Promise((ok) => stdin.once("drain", ok))
      }
    })
    await piped(["-f", "image2pipe", "-c:v", "png", "-i", "-", "-vf", scale, "-q:v", "4", out + ".jpg"],
      async (stdin) => { stdin.write(first) })
    console.log(JSON.stringify({ slug: job.slug, width: Math.trunc(info.w / 3) * 2, height: Math.trunc(info.h / 3) * 2, frames: info.frames, ms: Date.now() - started }))
  }
  ws.close()
} catch (error) {
  console.error(error.message)
  process.exitCode = 1
} finally {
  await close()
}
