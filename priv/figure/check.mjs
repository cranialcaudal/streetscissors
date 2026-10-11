// The rules a figure has to keep, read off its joints and its equipment with
// no picture drawn. What a person would otherwise have to notice by looking:
// a bar through the hips, a hand inside the head, a body nothing holds up.
//
//   node check.mjs <jobs.json>
//
// jobs.json is [{slug, track, muscles}], as for render.mjs. One line of JSON
// is printed per figure: {slug, problems: [{rule, text, frames}]}, `frames`
// the share of the loop the rule is broken for. Lengths are stage units: a
// standing figure is about 80 tall, so one unit is a little over 2 cm.
import { readFileSync, copyFileSync, mkdtempSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { dirname, join } from "node:path"
import { fileURLToPath, pathToFileURL } from "node:url"

const here = dirname(fileURLToPath(import.meta.url))
// figure3d.js is a module for the browser; node wants to be told so by its name
const scratch = mkdtempSync(join(tmpdir(), "figure-check-"))
copyFileSync(join(here, "figure3d.js"), join(scratch, "figure3d.mjs"))
const { prepare } = await import(pathToFileURL(join(scratch, "figure3d.mjs")).href)
rmSync(scratch, { recursive: true, force: true })

const MAT = 10, BAND = 12
const sub = (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]]
const add = (a, b) => [a[0] + b[0], a[1] + b[1], a[2] + b[2]]
const mul = (a, k) => [a[0] * k, a[1] * k, a[2] * k]
const dot = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
const len = (a) => Math.sqrt(dot(a, a))
const clamp = (x) => Math.max(0, Math.min(1, x))

// the nearest the segments a–b and c–d come to each other
function apart(a, b, c, d) {
  const u = sub(b, a), v = sub(d, c), w = sub(a, c)
  const uu = dot(u, u), uv = dot(u, v), vv = dot(v, v), uw = dot(u, w), vw = dot(v, w)
  const den = uu * vv - uv * uv
  let s = den > 1e-9 ? clamp((uv * vw - vv * uw) / den) : 0
  let t = vv > 1e-9 ? clamp((uv * s + vw) / vv) : 0
  s = uu > 1e-9 ? clamp((uv * t - uw) / uu) : 0
  return len(sub(add(a, mul(u, s)), add(c, mul(v, t))))
}

// The body as a few fat lines: enough to say what a bar has gone through.
function parts(J) {
  const out = [
    { name: "torso", a: J.pelvis, b: J.chest, r: 4.6, trunk: true },
    { name: "chest", a: J.chest, b: J.neck, r: 5.0, trunk: true },
    { name: "head", a: J.head, b: J.head, r: 4.2, head: true },
  ]
  for (const s of ["a", "b"]) {
    out.push({ name: "upper arm", a: J["sh_" + s], b: J["elbow_" + s], r: 2.2, arm: s })
    out.push({ name: "forearm", a: J["elbow_" + s], b: J["hand_" + s], r: 1.7, arm: s })
    out.push({ name: "thigh", a: J["hip_" + s], b: J["knee_" + s], r: 3.4, leg: s })
    out.push({ name: "shin", a: J["knee_" + s], b: J["foot_" + s], r: 2.2, leg: s })
  }
  return out
}

function frameProblems(track, J, things) {
  const found = []
  const say = (rule, text) => found.push({ rule, text })
  const body = parts(J)
  const hands = [J.hand_a, J.hand_b], feet = [J.foot_a, J.foot_b]
  const gear = things.filter((t) => t.mat !== MAT)

  for (const t of gear) {
    if (t.type === 0) {
      // a bar, a pole, a handle, a band or a cable
      let a = t.a, b = t.b
      const reach = t.r + 3.5
      const held = hands.some((h) => apart(a, b, h, h) < reach)
      if (t.mat === BAND) {
        // a band ends in a hand or round a foot: that end is not "through" anything
        const span = len(sub(b, a)), trim = Math.min(6, span * 0.4)
        // (or round the waist, as a parachute's cord or a sled's strap does)
        const near = (p) => [...hands, ...feet].some((q) => len(sub(p, q)) < 4) || len(sub(p, J.pelvis)) < 7
        if (span > 1e-6 && near(a)) a = add(a, mul(sub(b, a), trim / span))
        if (span > 1e-6 && near(b)) b = add(b, mul(sub(a, b), trim / span))
      }
      for (const p of body) {
        if (p.arm && held) continue
        const depth = t.r + p.r - apart(a, b, p.a, p.b)
        if (depth > (t.mat === BAND ? 2.2 : 1.8)) say("through", `${t.mat === BAND ? "a band or cable" : "a bar"} passes through the ${p.name}`)
      }
    } else if (t.type === 2) {
      // a ball, a bell, the head of a dumbbell
      const held = hands.some((h) => len(sub(h, t.a)) < t.r + 4.5)
      for (const p of body) {
        if (p.arm && held) continue
        const depth = t.r + p.r - apart(t.a, t.a, p.a, p.b)
        if (depth > Math.max(2.4, t.r * 0.55)) say("through", `a weight is inside the ${p.name}`)
      }
    } else if (t.type === 1) {
      // a box, a bench, a wall: the middle of the body may not be inside it
      for (const [name, q] of [["pelvis", J.pelvis], ["chest", J.chest], ["head", J.head], ["knee", J.knee_a], ["knee", J.knee_b]]) {
        const inside = [0, 1, 2].every((i) => Math.abs(q[i] - t.a[i]) < t.b[i] - 1.2)
        if (inside) say("inside", `the ${name} is inside a bench, box or wall`)
      }
    }
  }

  // the body through itself
  for (const s of ["a", "b"]) {
    const E = J["elbow_" + s], H = J["hand_" + s]
    for (const p of body.filter((p) => p.trunk)) {
      if (p.r + 1.7 - apart(E, H, p.a, p.b) > 3.0) say("self", `a forearm passes through the ${p.name}`)
    }
    if (len(sub(H, J.head)) < 3.0) say("self", "a hand is inside the head")
  }

  if (track.floor && track.view !== "plan") {
    // each with how far its surface is from its joint: a body lying down
    // rests on its back, five units under the middle of its pelvis
    const low = [["foot", J.foot_a, 2.0], ["foot", J.foot_b, 2.0], ["knee", J.knee_a, 2.6], ["knee", J.knee_b, 2.6], ["hand", J.hand_a, 1.2],
      ["hand", J.hand_b, 1.2], ["pelvis", J.pelvis, 4.8], ["head", J.head, 4.2], ["elbow", J.elbow_a, 1.8], ["elbow", J.elbow_b, 1.8]]
    for (const [name, q] of low) if (q[1] < -1.0) say("floor", `a ${name} is below the floor`)

    // What is under the lowest part of the body: the floor, or the top of a box.
    const under = (q) => {
      let top = 0
      for (const t of things) {
        if (t.type === 1 && Math.abs(q[0] - t.a[0]) < t.b[0] + 1 && Math.abs(q[2] - t.a[2]) < t.b[2] + 1) top = Math.max(top, Math.min(t.a[1] + t.b[1], q[1] + 0.5))
        if (t.type === 3 && len([q[0] - t.a[0], 0, q[2] - t.a[2]]) < Math.max(t.b[0], t.b[2])) top = Math.max(top, Math.min(t.a[1] + t.b[1], q[1] + 0.5))
      }
      return top
    }
    const clear = Math.min(...low.slice(0, 7).map(([, q, r]) => q[1] - r - under(q)))
    // hung from a bar, or stood, knelt or sat on one (a foot plate, a rail)
    const holds = [...hands, ...feet, J.knee_a, J.knee_b, J.pelvis]
    const hanging = gear.some((t) => t.type === 0 && holds.some((h) => apart(t.a, t.b, h, h) < t.r + 4.5))
    found.clear = hanging ? 0 : clear

    // Standing on its feet alone, the body's weight has to be over them.
    const grounded = feet.filter((f) => f[1] - under(f) < 4)
    const leaning = [...hands, J.knee_a, J.knee_b].some((q) => q[1] - under(q) < 4.5) || J.pelvis[1] - under(J.pelvis) < 7 || hanging ||
      gear.some((t) => hands.some((h) => (t.type === 1 ? [0, 1, 2].every((i) => Math.abs(h[i] - t.a[i]) < t.b[i] + 3) : false)))
    if (grounded.length && !leaning && J.pelvis[1] > 22) {
      const trunk = mul(add(J.pelvis, J.neck), 0.5)
      let mass = 0.5, x = trunk[0] * 0.5
      for (const [w, q] of [[0.08, J.head], [0.05, J.elbow_a], [0.05, J.elbow_b], [0.16, J.knee_a], [0.16, J.knee_b]]) { mass += w; x += q[0] * w }
      for (const t of gear) if ((t.type === 2 || t.type === 3) && hands.some((h) => len(sub(h, t.a)) < 12)) { mass += 0.06; x += t.a[0] * 0.06 }
      x /= mass
      const xs = grounded.flatMap((f) => [f[0] - 3, f[0] + 7])
      const off = x < Math.min(...xs) ? x - Math.min(...xs) : x > Math.max(...xs) ? x - Math.max(...xs) : 0
      found.off = off
    }
  }
  return found
}

const jobs = JSON.parse(readFileSync(process.argv[2], "utf8"))
for (const job of jobs) {
  const { frames } = prepare(job.track, job.tiers || job.muscles)
  const tally = new Map()
  let floats = Infinity, off = [], standing = 0
  for (const f of frames) {
    const found = frameProblems(job.track, f.J, f.things)
    for (const key of new Set(found.map((p) => p.rule + "|" + p.text))) tally.set(key, (tally.get(key) || 0) + 1)
    if (found.clear !== undefined) floats = Math.min(floats, found.clear)
    if (found.off !== undefined) { standing++; off.push(found.off) }
  }
  const problems = [...tally].map(([key, n]) => ({ rule: key.split("|")[0], text: key.split("|")[1], frames: +(n / frames.length).toFixed(2) }))
  // a moment's overlap as a limb swings past is not a fault; a tenth of the loop is
    .filter((p) => p.frames >= 0.1)
  if (floats !== Infinity && floats > 2.5) problems.push({ rule: "support", text: `nothing is under it: it never comes nearer the floor than ${floats.toFixed(1)}`, frames: 1 })
  const far = off.filter((o) => Math.abs(o) > 6)
  if (standing && far.length / frames.length >= 0.5) {
    const worst = far.reduce((a, b) => (Math.abs(b) > Math.abs(a) ? b : a))
    problems.push({ rule: "balance", text: `its weight is ${Math.abs(worst).toFixed(0)} ${worst < 0 ? "behind" : "ahead of"} its feet with nothing to lean on`, frames: +(far.length / frames.length).toFixed(2) })
  }
  console.log(JSON.stringify({ slug: job.slug, problems }))
}
