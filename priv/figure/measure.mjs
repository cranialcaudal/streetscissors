// The figure against the tape: its own breadths, depths and girths beside a
// man's, so the body is corrected by measurement and not by eye.
//
//   node measure.mjs <jobs.json> [--json]
//
// jobs.json is [{track}], one figure standing upright with its feet flat
// (`mix fitness.film --measure` writes it). Nothing is drawn: the figure's
// solid is the one the shader marches (`solid/1` in figure3d.js), and a
// measurement is where a line from inside it comes out.
//
// The men are ANSUR II, the US Army's survey of 2012 (public data, 4,082
// men). The figure is drawn lean, so each reference is the mean of the 609
// men whose body-mass index was 21 to 24, as a share of their mean stature
// (1,759 mm). A measure is taken on the figure the way the survey took it as
// nearly as a figure allows; where it cannot be, the line says so.
import { readFileSync, copyFileSync, mkdtempSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { dirname, join } from "node:path"
import { fileURLToPath, pathToFileURL } from "node:url"

const here = dirname(fileURLToPath(import.meta.url))
const scratch = mkdtempSync(join(tmpdir(), "figure-measure-"))
copyFileSync(join(here, "figure3d.js"), join(scratch, "figure3d.mjs"))
const { prepare, body, solid } = await import(pathToFileURL(join(scratch, "figure3d.mjs")).href)
rmSync(scratch, { recursive: true, force: true })

// share of stature, lean men (see above)
const MEN = {
  acromial_height: 0.8165, suprasternale_height: 0.8159, trochanterion_height: 0.5152, crotch_height: 0.4853,
  knee_height: 0.2781, malleolus_height: 0.0407,
  bideltoid_breadth: 0.2711, chest_depth: 0.1276, chest_girth: 0.5448,
  waist_breadth: 0.1643, waist_depth: 0.1149, waist_girth: 0.4641,
  hip_breadth: 0.1838, buttock_depth: 0.1231, buttock_girth: 0.5316,
  thigh_girth: 0.3173, lower_thigh_girth: 0.2135, calf_girth: 0.206, ankle_girth: 0.124,
  biceps_girth_flexed: 0.1831, forearm_girth_flexed: 0.1644, wrist_girth: 0.0967,
  neck_girth: 0.2122, head_breadth: 0.0864, head_length: 0.1124, head_girth: 0.3225,
  acromion_radiale_length: 0.1902, radiale_stylion_length: 0.1524, elbow_grip_length: 0.1974,
  foot_length: 0.153, foot_breadth: 0.0565,
}
// Left out: the survey's chest breadth. It is taken with a caliper pressed to
// the ribs under the arms (275 mm), where a figure has its lats; the girth
// and the depth of the chest say what the breadth would.
// the heights the survey measured the trunk at
const AT = { chest: 0.7355, waist: 0.6056, buttock: 0.5073 }

const add = (a, b) => [a[0] + b[0], a[1] + b[1], a[2] + b[2]]
const sub = (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]]
const mul = (a, k) => [a[0] * k, a[1] * k, a[2] * k]
const mix = (a, b, t) => add(a, mul(sub(b, a), t))
const len = (a) => Math.hypot(a[0], a[1], a[2])
const norm = (a) => mul(a, 1 / len(a))
const cross = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]

// how far from a point inside the solid, along dir, its surface is
function exit(D, from, dir, max = 60) {
  let depth = D(from)
  if (depth > 0) return null
  // inside, the field says about how deep the point is: go most of that way
  // at a time, never less than a twentieth of a unit
  let lo = 0, hi = 0
  while (depth <= 0) {
    lo = hi
    hi += Math.max(-depth * 0.6, 0.05)
    if (hi > max) return max
    depth = D(add(from, mul(dir, hi)))
  }
  for (let i = 0; i < 14; i++) {
    const mid = (lo + hi) / 2
    if (D(add(from, mul(dir, mid))) <= 0) lo = mid
    else hi = mid
  }
  return lo
}

// how far from a point outside the solid, along dir, its surface is
function enter(D, from, dir, max = 60) {
  const step = 0.05
  for (let t = 0; t < max; t += step) {
    if (D(add(from, mul(dir, t))) <= 0) {
      let lo = t - step, hi = t
      for (let i = 0; i < 18; i++) {
        const mid = (lo + hi) / 2
        if (D(add(from, mul(dir, mid))) <= 0) hi = mid
        else lo = mid
      }
      return hi
    }
  }
  return null
}

// The slice of the solid through c in the plane of the unit vectors u and w,
// as seen from c: how far it runs along each, and the length of its edge.
// `limit` may stop a ray short: a thigh's slice ends at the body's midline,
// and an arm's before it runs on into whatever the arm is beside.
function slice(D, c, u, w, limit = () => Infinity) {
  const n = 96, pts = []
  for (let i = 0; i < n; i++) {
    const a = (2 * Math.PI * i) / n
    const dir = add(mul(u, Math.cos(a)), mul(w, Math.sin(a)))
    const r = Math.min(exit(D, c, dir) ?? 0, limit(dir))
    pts.push([Math.cos(a) * r, Math.sin(a) * r])
  }
  let girth = 0
  for (let i = 0; i < n; i++) girth += Math.hypot(pts[i][0] - pts[(i + 1) % n][0], pts[i][1] - pts[(i + 1) % n][1])
  const span = (k) => Math.max(...pts.map((p) => p[k])) - Math.min(...pts.map((p) => p[k]))
  return { girth, u: span(0), w: span(1) }
}

const X = [1, 0, 0], Y = [0, 1, 0], Z = [0, 0, 1]

const [job] = JSON.parse(readFileSync(process.argv[2], "utf8"))
const stood = prepare(job.track, []).frames[0].J

// The same figure with its arms somewhere else: `arm(side, shoulder)` gives
// the elbow and the hand. D is its solid; T is the solid with the arms taken
// off, since a tape round a chest passes inside the arms.
function posed(arm) {
  const J = structuredClone(stood)
  for (const [s, k] of [[1, "a"], [-1, "b"]]) [J["elbow_" + k], J["hand_" + k]] = arm(s, J["sh_" + k])
  const shapes = body(J, new Map(), {})
  const armless = (list) => list.filter((shape) => shape.part !== "arm")
  return { J, D: solid(shapes), T: solid({ cones: armless(shapes.cones), ells: armless(shapes.ells) }) }
}
const UPPER = 14, FORE = 15
const along = (S, dir) => [add(S, mul(dir, UPPER)), add(S, mul(dir, UPPER + FORE))]
const rad = (deg) => (deg * Math.PI) / 180
// arms hanging; arms held 40° out from the sides, clear of the trunk; the
// upper arm out level with the forearm upright, the muscle-man's pose the
// survey measured a flexed arm in; and the upper arm hanging with the forearm
// level, which it measured the arm's lengths in
const down = posed((s, S) => along(S, norm([0.02, -1, 0.05 * s])))
const apart = posed((s, S) => along(S, [0, -Math.cos(rad(40)), s * Math.sin(rad(40))]))
const flexed = posed((s, S) => [add(S, [0, 0, s * UPPER]), add(S, [0, FORE, s * UPPER])])
const bent = posed((s, S) => [add(S, [0, -UPPER, s]), add(S, [FORE, -UPPER, s])])

const { J, D } = apart
const top = J.head[1] + exit(D, J.head, Y)
const rows = []
const row = (key, name, value, note = "") => rows.push({ key, name, value, note })

// the middle of the trunk at a height
const spine = (y) => {
  const [a, b] = y < J.chest[1] ? [J.pelvis, J.chest] : [J.chest, J.neck]
  return [mix(a, b, (y - a[1]) / (b[1] - a[1]))[0], y, 0]
}
const trunk = (y) => slice(down.T, spine(y), X, Z)
const heights = (from, to, step = 0.25) => Array.from({ length: Math.floor((to - from) / step) + 1 }, (_, i) => from + i * step)

// heights
const shoulderTop = (P) => P.J.sh_a[1] + 9 - enter(P.D, add(P.J.sh_a, [0, 9, 0]), [0, -1, 0])
row("acromial_height", "top of the shoulder", shoulderTop(down))
row("suprasternale_height", "top of the breastbone", J.neck[1] - 1.8, "the notch the collar bones meet at")
row("trochanterion_height", "hip joint", J.hip_a[1], "the survey's point is the bone beside the joint")
// the highest a bar between the legs would go
const crotch = Math.min(...heights(J.pelvis[0] - 2, J.pelvis[0] + 2, 0.5).map((x) => J.knee_a[1] + (enter(D, [x, J.knee_a[1], 0], Y) ?? 99)))
row("crotch_height", "crotch", crotch)
row("knee_height", "knee", J.knee_a[1])
row("malleolus_height", "ankle", J.foot_a[1])

// the trunk
const shoulders = heights(J.sh_a[1] - 9, J.sh_a[1] + 2).map((y) => {
  const reach = (s) => Math.max(...[-1.5, 0, 1.5].map((dx) => 30 - (enter(down.D, [down.J.sh_a[0] + dx, y, 30 * s], [0, 0, -s]) ?? 30)))
  return reach(1) + reach(-1)
})
row("bideltoid_breadth", "across the shoulders", Math.max(...shoulders), "arms hanging")
const chest = trunk(AT.chest * top), waist = trunk(AT.waist * top)
row("chest_depth", "chest, front to back", chest.u)
row("chest_girth", "round the chest", chest.girth)
row("waist_breadth", "waist, side to side", waist.w, "at the navel's height")
row("waist_depth", "waist, front to back", waist.u)
row("waist_girth", "round the waist", waist.girth)
const hips = heights(crotch, AT.waist * top, 0.5).map((y) => ({ y, ...trunk(y) }))
const widest = hips.reduce((a, b) => (b.w > a.w ? b : a)), deepest = hips.reduce((a, b) => (b.u > a.u ? b : a))
row("hip_breadth", "hips, side to side", widest.w, `widest ${((widest.y / top) * 100).toFixed(0)}% up`)
row("buttock_depth", "seat, front to back", deepest.u, `deepest ${((deepest.y / top) * 100).toFixed(0)}% up`)
row("buttock_girth", "round the seat", deepest.girth)
const narrowest = heights(crotch + 4, AT.chest * top, 0.5).map((y) => ({ y, ...trunk(y) })).reduce((a, b) => (b.w < a.w ? b : a))

// the legs: level slices of one leg, stopped at the midline where the two meet
const leg = (y) => {
  const [a, b] = y > J.knee_a[1] ? [J.hip_a, J.knee_a] : [J.knee_a, J.foot_a]
  const c = mix(a, b, (a[1] - y) / (a[1] - b[1]))
  return slice(D, c, X, Z, (dir) => (dir[2] < -1e-6 ? c[2] / -dir[2] : Infinity)).girth
}
row("thigh_girth", "round the top of the thigh", leg(crotch - 0.8))
row("lower_thigh_girth", "round the thigh above the knee", leg(J.knee_a[1] + 2.6))
row("calf_girth", "round the calf", Math.max(...heights(J.foot_a[1] + 6, J.knee_a[1] - 3, 0.5).map(leg)))
row("ankle_girth", "round the ankle", Math.min(...heights(J.foot_a[1] + 2.2, J.foot_a[1] + 6, 0.4).map(leg)))

// the arms: slices square to the bone
const limb = (P, a, b, t) => {
  const dir = norm(sub(b, a)), u = norm(cross(dir, Math.abs(dir[1]) > 0.9 ? X : Y))
  return slice(P.D, mix(a, b, t), u, cross(dir, u), () => 7).girth
}
const fractions = (from, to) => heights(from, to, 0.04)
row("biceps_girth_flexed", "round the upper arm, bent", Math.max(...fractions(0.5, 0.85).map((t) => limb(flexed, flexed.J.sh_a, flexed.J.elbow_a, t))))
row("forearm_girth_flexed", "round the forearm, bent", Math.max(...fractions(0.3, 0.6).map((t) => limb(flexed, flexed.J.elbow_a, flexed.J.hand_a, t))))
// the wrist is where the arm is thinnest between the forearm and the hand
const narrow = fractions(0.6, 0.97).map((t) => ({ t, girth: limb(apart, J.elbow_a, J.hand_a, t) })).reduce((a, b) => (b.girth < a.girth ? b : a))
row("wrist_girth", "round the wrist", narrow.girth)
row("acromion_radiale_length", "shoulder top to the elbow joint", shoulderTop(down) - down.J.elbow_a[1], "arm hanging")
row("radiale_stylion_length", "elbow joint to the wrist", narrow.t * FORE, "a hand holding nothing")
const E = bent.J.elbow_a
row("elbow_grip_length", "back of the elbow to the grip", bent.J.hand_a[0] - (E[0] - 8 + enter(bent.D, add(E, [-8, 0, 0]), X)), "the hand's point is the middle of a fist")

// The neck and the head. The head is a ball (the author's drawing of one),
// so it is as broad as it is long: against a man's head, which is three
// quarters as broad as long, it will always measure broad.
const neckDir = norm(sub(J.head, J.neck)), neckU = norm(cross(neckDir, Z))
row("neck_girth", "round the neck", Math.min(...fractions(0.15, 0.6).map((t) => slice(D, mix(J.neck, J.head, t), neckU, Z).girth)))
const head = heights(J.head[1] - 1.5, J.head[1] + 1.5).map((y) => slice(D, [J.head[0], y, 0], X, Z))
row("head_breadth", "head, side to side", Math.max(...head.map((h) => h.w)), "a ball, by design")
row("head_length", "head, front to back", Math.max(...head.map((h) => h.u)))
row("head_girth", "round the head", Math.max(...head.map((h) => h.girth)), "a ball, by design")

// the foot, which is a shoe
const sole = slice(D, [mix(J.foot_a, J.toe_a, 0.4)[0], 1.3, J.foot_a[2]], X, Z)
row("foot_length", "foot, heel to toe", sole.u, "in a shoe")
row("foot_breadth", "foot, side to side", sole.w, "in a shoe")

// What is printed: the figure's share of its own height, the men's, and one
// over the other. A figure as tall as the mean lean man (1,759 mm) would
// measure the centimetres shown. With --json, the same as one object, for a
// test to hold the body to.
const table = rows.map((r) => ({ key: r.key, name: r.name, note: r.note, share: r.value / top, men: MEN[r.key], ratio: r.value / top / MEN[r.key] }))
const widestShoulders = Math.max(...shoulders)
if (process.argv.includes("--json")) {
  console.log(JSON.stringify({
    stature: top, rows: table, waist_to_hips: waist.w / widest.w, shoulders_to_hips: widestShoulders / widest.w,
    waist_narrowest_at: narrowest.y / top,
  }))
  process.exit(0)
}
const pad = (s, n) => String(s).padEnd(n), lead = (s, n) => String(s).padStart(n)
console.log(`The figure is ${top.toFixed(1)} units tall, so a unit is ${(175.9 / top).toFixed(2)} cm of a man of 175.9 cm.`)
console.log(`${pad("", 32)}${lead("figure", 8)}${lead("men", 8)}${lead("ratio", 8)}${lead("cm", 8)}`)
const off = table.filter((r) => Math.abs(r.ratio - 1) > 0.08)
for (const r of table) {
  const pct = (x) => (x * 100).toFixed(1) + "%"
  console.log(`${pad(r.name, 32)}${lead(pct(r.share), 8)}${lead(pct(r.men), 8)}${lead(r.ratio.toFixed(2), 8)}${lead((r.share * 175.9).toFixed(1), 8)}${off.includes(r) ? "  <" : "   "} ${r.note}`)
}
console.log(`\nThe waist is ${(waist.w / widest.w).toFixed(2)} of the hips across (men: ${(MEN.waist_breadth / MEN.hip_breadth).toFixed(2)}), and narrowest ${((narrowest.y / top) * 100).toFixed(0)}% up at ${((narrowest.w / top) * 100).toFixed(1)}% of the height.`)
console.log(`The shoulders are ${(widestShoulders / widest.w).toFixed(2)} of the hips across (men: ${(MEN.bideltoid_breadth / MEN.hip_breadth).toFixed(2)}).`)
console.log(off.length ? `${off.length} of ${table.length} measures are more than 8% from the men's (marked <).` : `Every measure is within 8% of the men's.`)
