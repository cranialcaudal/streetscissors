// The 3D figure: a body sculpted from a pose, with its muscles as separate
// volumes that can be lit.
//
// A track (Web.Fitness.Figure.track/2) is a list of frames, each the 2D
// joints of the figure on its stage. This file lifts a frame into 3D (the
// stage's plane, plus the width of a body), builds the body round the joints
// out of rounded cones and ellipsoids, and draws it by marching rays through
// their signed distance field. Nothing here is a mesh, and nothing is loaded:
// the figure is the same forty-odd shapes in every clip, moved.
//
// World: x is the way the figure faces, y is up, z is toward its near side.
// One unit is one stage unit; a standing figure is about 80 tall.

const G = 101 // stage y of the floor the figure stands on

const v = {
  add: (a, b) => [a[0] + b[0], a[1] + b[1], a[2] + b[2]],
  sub: (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]],
  mul: (a, k) => [a[0] * k, a[1] * k, a[2] * k],
  dot: (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2],
  cross: (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]],
  len: (a) => Math.hypot(a[0], a[1], a[2]),
  mix: (a, b, t) => [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t],
  norm: (a, fallback = [0, 1, 0]) => {
    const l = Math.hypot(a[0], a[1], a[2])
    return l < 1e-5 ? fallback : [a[0] / l, a[1] / l, a[2] / l]
  },
  // the part of a that is square to the unit vector n
  reject: (a, n) => v.sub(a, v.mul(n, v.dot(a, n))),
}

export const MUSCLES = [
  "chest", "lats", "traps", "delts", "biceps", "triceps", "forearms", "abs", "obliques",
  "lowback", "glutes", "quads", "hamstrings", "calves", "adductors", "serratus", "neck",
]

const SKIN = 0, SHORTS = 1, SHOES = 2, HAIR = 3
const MAT = 10, GEAR = 11, BAND = 12

// How a track is seen: from the side, from the front, or (a front view with
// no floor) from above, the figure lying face down.
function mode(track) {
  if (track.view === "front") return track.floor ? "front" : "plan"
  return "side"
}

// ── Lifting a frame's joints into 3D ─────────────────────────────────────

// How far each hand is from the middle of the body. From the side both hands
// are in one place whether they hang at the hips or hold one thing between
// them, so it is what they hold that says which: one thing in both hands
// brings them together, and anything else leaves them a shoulder's width apart.
function handGap(track) {
  const held = track.props.find((p) => p.hold === "hands")
  if (held) return { kettlebell: 2.3, ball: 4.6, bar: 9.6, dumbbell: 3.0 }[held.kind] ?? 3
  if (track.props.some((p) => p.kind === "line" && p.ends.includes("hands"))) return 2.4
  return 9.4
}

// Where the elbow is, given the shoulder and the hand in 3D: the flat pose
// placed it for a flat arm, and an arm that also reaches sideways would
// otherwise be drawn too long. `hint` is the flat pose's elbow, which says
// which way the arm bends.
const UPPER = 14, FORE = 15
function elbow(S, H, hint) {
  const reach = v.sub(H, S)
  const d = Math.min(Math.max(v.len(reach), 1.2), UPPER + FORE - 0.05)
  const dir = v.norm(reach, [0, -1, 0])
  const along = (UPPER * UPPER - FORE * FORE + d * d) / (2 * d)
  const rise = Math.sqrt(Math.max(UPPER * UPPER - along * along, 0))
  const out = v.norm(v.reject(v.sub(hint, S), dir), v.norm(v.reject([0, -1, 0], dir), [1, 0, 0]))
  return v.add(v.add(S, v.mul(dir, along)), v.mul(out, rise))
}

export function lift(track, f) {
  const m = mode(track)
  const turn = (f.turn * Math.PI) / 180
  const J = {}

  if (m === "side") {
    const at = (p, z) => [p[0], G - p[1], z]
    const shz = 8.0 * Math.cos(turn)
    const gap = f.spread ?? handGap(track)
    const side = f.side * 9
    J.pelvis = at(f.pelvis, 0); J.chest = at(f.chest, 0); J.neck = at(f.neck, 0)
    J.nape = at(f.nape, 0); J.head = at(f.head, 0)
    J.sh_a = at(f.sh_a, shz); J.sh_b = at(f.sh_b, -shz)
    J.hip_a = at(f.hip_a, 4.8); J.hip_b = at(f.hip_b, -4.8)
    J.knee_a = at(f.knee_a, 5.4); J.knee_b = at(f.knee_b, -5.4)
    J.foot_a = at(f.foot_a, 5.2); J.foot_b = at(f.foot_b, -5.2)
    J.toe_a = at(f.toe_a, 5.8); J.toe_b = at(f.toe_b, -5.8)
    J.hand_a = at(f.hand_a, gap + side); J.hand_b = at(f.hand_b, -gap + side)
    // flare swings the elbow out of the picture's plane, toward its own side
    const flare = f.flare || 0
    const hint = (S, flat, out) => v.add(S, v.mix(v.sub(flat, S), [0, 0, out], flare))
    J.elbow_a = elbow(J.sh_a, J.hand_a, hint(J.sh_a, at(f.elbow_a, (shz + gap + side) / 2 + 2.0), 30))
    J.elbow_b = elbow(J.sh_b, J.hand_b, hint(J.sh_b, at(f.elbow_b, (-shz - gap + side) / 2 - 2.0), -30))
  } else if (m === "front") {
    const at = (p, x) => [x, G - p[1], -(p[0] - 80)]
    for (const k of ["pelvis", "chest", "neck", "nape", "head", "sh_a", "sh_b", "hip_a", "hip_b", "knee_a", "knee_b", "foot_a", "foot_b"]) J[k] = at(f[k], 0)
    J.elbow_a = at(f.elbow_a, 0.5); J.elbow_b = at(f.elbow_b, 0.5)
    J.hand_a = at(f.hand_a, 2.0); J.hand_b = at(f.hand_b, 2.0)
    // toes point at the viewer and a little outward
    J.toe_a = v.add(J.foot_a, [6.6, f.foot_a[1] > 96 ? 0 : -2, 1.2])
    J.toe_b = v.add(J.foot_b, [6.6, f.foot_b[1] > 96 ? 0 : -2, -1.2])
  } else {
    // lying face down, head toward +x, seen from above
    const at = (p, h) => [60 - p[1], h, -(p[0] - 80)]
    J.pelvis = at(f.pelvis, 5.4); J.chest = at(f.chest, 5.8); J.neck = at(f.neck, 6.0)
    J.nape = at(f.nape, 6.0); J.head = at(f.head, 5.8)
    J.sh_a = at(f.sh_a, 6.2); J.sh_b = at(f.sh_b, 6.2)
    J.hip_a = at(f.hip_a, 5.0); J.hip_b = at(f.hip_b, 5.0)
    J.knee_a = at(f.knee_a, 3.6); J.knee_b = at(f.knee_b, 3.6)
    J.foot_a = at(f.foot_a, 2.6); J.foot_b = at(f.foot_b, 2.6)
    J.toe_a = v.add(J.foot_a, [-6.4, -1.2, 0.6]); J.toe_b = v.add(J.foot_b, [-6.4, -1.2, -0.6])
    // the arms lift off the floor a little, which is the exercise
    J.elbow_a = at(f.elbow_a, 6.4); J.elbow_b = at(f.elbow_b, 6.4)
    J.hand_a = at(f.hand_a, 7.0); J.hand_b = at(f.hand_b, 7.0)
  }
  return J
}

// ── The body round the joints ────────────────────────────────────────────

export function body(J, hot) {
  const cones = [], ells = []
  const h = (muscle) => (muscle && hot.has(muscle) ? 1 : 0)
  const cone = (a, b, ra, rb, muscle = null, mat = SKIN) => {
    if (v.len(v.sub(a, b)) < 0.05) b = v.add(b, [0, 0.05, 0])
    cones.push({ a, b, ra, rb, hot: h(muscle), mat })
  }
  // ax is the first axis, ay roughly the second; radii are along ax, ay and ax × ay
  const ell = (c, ax, ay, radii, muscle = null, mat = SKIN) => {
    const x = v.norm(ax, [1, 0, 0])
    const y = v.norm(v.reject(ay, x), v.norm(v.cross(x, [0.3, 0.2, 0.9])))
    ells.push({ c, x, y, radii, hot: h(muscle), mat })
  }

  const lat = v.norm(v.sub(J.sh_a, J.sh_b), [0, 0, 1])
  const latH = v.norm(v.sub(J.hip_a, J.hip_b), lat)
  const upLo = v.norm(v.sub(J.chest, J.pelvis))
  const upUp = v.norm(v.sub(J.neck, J.chest), upLo)
  const frLo = v.norm(v.cross(upLo, latH), [1, 0, 0])
  const frUp = v.norm(v.cross(upUp, lat), frLo)
  const P = (base, ...terms) => terms.reduce((acc, [dir, k]) => v.add(acc, v.mul(dir, k)), base)

  // trunk: three masses that melt into one, and the muscles lying in them
  // almost flush, so they shape the surface without standing off it
  const waist = v.mix(J.pelvis, J.chest, 0.55)
  ell(P(J.pelvis, [upLo, 1.2]), frLo, upLo, [4.8, 5.3, 7.0], null, SHORTS)
  for (const s of [1, -1]) ell(P(J.pelvis, [latH, 3.0 * s], [frLo, -2.3], [upLo, -0.5]), frLo, upLo, [3.6, 4.5, 3.7], "glutes", SHORTS)
  ell(waist, frLo, upLo, [4.4, 8.2, 6.3])
  ell(P(waist, [frLo, 2.2]), frLo, upLo, [2.4, 7.2, 3.9], "abs")
  for (const s of [1, -1]) ell(P(waist, [latH, 4.3 * s], [frLo, 0.3]), frLo, upLo, [3.0, 6.0, 2.2], "obliques")
  ell(P(v.mix(J.pelvis, J.chest, 0.5), [frLo, -2.4]), frLo, upLo, [2.2, 7.0, 4.0], "lowback")

  const rib = v.mix(J.chest, J.neck, 0.45)
  ell(rib, frUp, upUp, [5.6, 9.6, 8.2])
  for (const s of [1, -1]) {
    ell(P(rib, [upUp, 2.7], [frUp, 3.2], [lat, 3.7 * s]), frUp, upUp, [2.5, 3.5, 4.2], "chest")
    ell(P(rib, [upUp, -1.2], [frUp, -2.0], [lat, 5.9 * s]), frUp, upUp, [3.0, 7.4, 2.7], "lats")
    ell(P(rib, [upUp, -3.2], [frUp, 1.2], [lat, 6.9 * s]), frUp, upUp, [2.6, 3.8, 1.6], "serratus")
  }
  ell(P(J.neck, [frUp, -2.0], [upUp, -2.2]), frUp, upUp, [2.6, 5.4, 6.0], "traps")
  // the shoulder girdle: one bar from shoulder to shoulder, not two balls
  cone(J.sh_a, J.sh_b, 3.0, 3.0)

  // neck and head
  const crown = v.norm(v.sub(J.head, J.nape), upUp)
  const face = v.norm(v.reject(frUp, crown), frUp)
  const ear = v.norm(v.cross(crown, face), lat)
  cone(P(J.neck, [upUp, -1.2]), P(J.nape, [crown, 1.8]), 2.9, 2.6, "neck")
  const skull = P(J.head, [crown, -0.4])
  ell(skull, face, crown, [4.4, 5.2, 4.0])
  ell(P(skull, [face, 1.2], [crown, -2.9]), face, crown, [3.2, 2.9, 3.0])
  ell(P(skull, [face, 3.9], [crown, -3.9]), face, crown, [1.3, 1.2, 1.6])
  ell(P(skull, [face, 4.3], [crown, -1.0]), face, crown, [0.9, 1.3, 0.7])
  ell(P(skull, [face, 3.6], [crown, 0.9]), face, crown, [1.2, 0.7, 3.0])
  for (const s of [1, -1]) ell(P(skull, [ear, 3.9 * s], [crown, -0.8], [face, -0.4]), face, crown, [0.9, 1.3, 0.5])
  ell(P(skull, [crown, 1.3], [face, -1.1]), face, crown, [4.5, 4.6, 4.3], null, HAIR)

  // arms
  for (const [s, S, E, H] of [[1, J.sh_a, J.elbow_a, J.hand_a], [-1, J.sh_b, J.elbow_b, J.hand_b]]) {
    cone(v.mix(J.nape, J.neck, 0.5), S, 2.4, 2.1, "traps")
    ell(P(S, [lat, 0.3 * s], [upUp, -0.7]), frUp, upUp, [3.1, 3.8, 3.0], "delts")
    const along = v.norm(v.sub(E, S), [0, -1, 0])
    let fr = v.reject(v.sub(H, E), along)
    fr = v.len(fr) < 0.8 ? v.norm(v.reject(frUp, along), [1, 0, 0]) : v.norm(fr)
    cone(S, E, 2.6, 2.2)
    ell(P(v.mix(S, E, 0.52), [fr, 0.8]), along, fr, [5.4, 2.2, 2.1], "biceps")
    ell(P(v.mix(S, E, 0.5), [fr, -0.9]), along, fr, [6.0, 2.2, 2.2], "triceps")
    const reachDir = v.norm(v.sub(H, E), along)
    cone(E, H, 2.1, 1.5, "forearms")
    ell(v.mix(E, H, 0.3), reachDir, fr, [4.6, 2.3, 2.1], "forearms")
    ell(P(H, [reachDir, 1.7]), reachDir, fr, [2.6, 1.1, 1.9])
    ell(P(H, [reachDir, 0.6], [fr, 1.1]), reachDir, fr, [1.6, 0.8, 0.8])
  }

  // legs
  for (const [s, Hp, K, A, T] of [[1, J.hip_a, J.knee_a, J.foot_a, J.toe_a], [-1, J.hip_b, J.knee_b, J.foot_b, J.toe_b]]) {
    const along = v.norm(v.sub(K, Hp), [0, -1, 0])
    let fr = v.reject(v.sub(K, v.mix(Hp, A, 0.5)), v.norm(v.sub(A, Hp), along))
    fr = v.len(fr) < 0.8 ? v.norm(v.reject(frLo, along), [1, 0, 0]) : v.norm(v.reject(fr, along), frLo)
    const inner = v.mul(latH, -s)
    cone(Hp, K, 4.2, 2.9)
    cone(Hp, v.mix(Hp, K, 0.36), 4.6, 4.2, null, SHORTS)
    ell(P(v.mix(Hp, K, 0.48), [fr, 1.3]), along, fr, [8.6, 3.0, 3.5], "quads")
    ell(P(v.mix(Hp, K, 0.46), [fr, -1.3]), along, fr, [8.4, 2.9, 3.4], "hamstrings")
    ell(P(v.mix(Hp, K, 0.34), [inner, 1.6]), along, fr, [6.4, 2.5, 2.3], "adductors")
    const shin = v.norm(v.sub(A, K), along)
    const frS = v.norm(v.reject(fr, shin), fr)
    cone(K, A, 2.6, 1.7)
    ell(P(v.mix(K, A, 0.3), [frS, -0.9]), shin, frS, [5.6, 2.4, 2.5], "calves")
    // a shoe: a long low toe box and a heel, flat underneath
    const toe = v.norm(v.sub(T, A), [1, 0, 0])
    const sole = v.norm(v.reject(shin, toe), [0, -1, 0])
    ell(P(v.mix(A, T, 0.55), [sole, 0.5]), toe, sole, [4.8, 1.7, 2.3], null, SHOES)
    ell(P(A, [toe, -0.8], [sole, 0.2]), toe, sole, [2.5, 2.1, 2.1], null, SHOES)
  }
  return { cones, ells }
}

// ── What is held, stood on or pulled ─────────────────────────────────────

export function gear(track, i, J) {
  const out = []
  const m = mode(track)
  const capsule = (a, b, r, mat = GEAR) => out.push({ type: 0, a, b, r, mat })
  const box = (c, half, mat = GEAR, round = 0.4) => out.push({ type: 1, a: c, b: half, r: round, mat })
  const sphere = (c, r, mat = GEAR) => out.push({ type: 2, a: c, b: [0, 0, 0], r, mat })
  const blob = (c, radii, mat = GEAR) => out.push({ type: 3, a: c, b: radii, r: 0, mat })
  // a point on the stage, at a depth
  const at = (p, z = 0) => (m === "side" ? [p[0], G - p[1], z] : m === "front" ? [z, G - p[1], -(p[0] - 80)] : [60 - p[1], 3, -(p[0] - 80)])
  const depthOf = (hold) => (hold === "hand_a" ? J.hand_a : hold === "hand_b" ? J.hand_b : hold === "foot_a" ? J.foot_a : hold === "foot_b" ? J.foot_b : null)
  const across = m === "side" ? [0, 0, 1] : [1, 0, 0]
  const zOf = (p3) => (m === "side" ? p3[2] : p3[0])

  for (const p of track.props) {
    if (p.kind === "mat") {
      if (m === "side") box([(p.from + p.to) / 2, 0.35, 0], [(p.to - p.from) / 2, 0.35, 15], MAT, 0.3)
      else box([0, 0.35, 0], [15, 0.35, (p.to - p.from) / 2], MAT, 0.3)
    } else if (p.kind === "box") {
      if (m === "side") box([p.x + p.w / 2, p.h / 2, 0], [p.w / 2, p.h / 2, 11])
      else box([0, p.h / 2, -(p.x + p.w / 2 - 80)], [11, p.h / 2, p.w / 2])
    } else if (p.kind === "block") {
      if (p.w > 100 && p.h <= 1.5) continue // the water's surface is drawn by the shader
      const cy = G - (p.y + p.h / 2)
      const deep = p.w < 7 ? 14 : 12
      if (m === "side") box([p.x + p.w / 2, cy, 0], [p.w / 2, p.h / 2, deep])
      else box([-8, cy, -(p.x + p.w / 2 - 80)], [p.w < 7 ? 14 : 6, p.h / 2, p.w / 2])
    } else if (p.kind === "disc") {
      const c = at(p.at)
      if (p.ball) sphere(c, p.r)
      else capsule(v.add(c, v.mul(across, -14)), v.add(c, v.mul(across, 14)), Math.max(p.r * 0.55, 1.0))
    } else if (p.kind === "dome") {
      if (m === "side") blob([p.x, 0, 0], [p.w / 2, p.h + 2, p.w / 2])
      else blob([0, 0, -(p.x - 80)], [p.w / 2, p.h + 2, p.w / 2])
    } else if (p.kind === "line") {
      const [e1, e2] = p.at[i]
      const d1 = depthOf(p.ends[0]), d2 = depthOf(p.ends[1])
      const z1 = d1 ? zOf(d1) : d2 ? zOf(d2) : 0, z2 = d2 ? zOf(d2) : d1 ? zOf(d1) : 0
      // a fixed end sits at the line's own depth when it has one
      const a = p.ends[0] === "hands" ? v.mix(J.hand_a, J.hand_b, 0.5) : d1 ?? at(e1, p.depth || z1)
      const b = p.ends[1] === "hands" ? v.mix(J.hand_a, J.hand_b, 0.5) : d2 ?? at(e2, p.depth || z2)
      capsule(a, b, p.style === "pole" ? 1.0 : 0.45, p.style === "pole" ? GEAR : BAND)
    } else {
      // held: the grip is where the hand (or the middle of the hands) is
      const [g2, w2] = p.at[i]
      const hand = p.hold === "hand_a" ? J.hand_a : p.hold === "hand_b" ? J.hand_b : v.mix(J.hand_a, J.hand_b, 0.5)
      const drop = [w2[0] - g2[0], -(w2[1] - g2[1]), 0]
      const off = m === "side" ? drop : [0, drop[1], -drop[0]]
      const grip = hand, weight = v.add(hand, off)
      if (p.kind === "kettlebell") {
        const a = v.add(grip, v.mul(across, -2.3)), b = v.add(grip, v.mul(across, 2.3))
        capsule(a, b, 0.75)
        const top = v.add(weight, v.mul(v.norm(v.sub(grip, weight), [0, 1, 0]), 3.4))
        capsule(a, v.add(top, v.mul(across, -1.6)), 0.7)
        capsule(b, v.add(top, v.mul(across, 1.6)), 0.7)
        sphere(weight, 4.3)
      } else if (p.kind === "dumbbell") {
        const axis = m === "side" ? [1, 0, 0] : [0, 0, 1]
        capsule(v.add(grip, v.mul(axis, -3.2)), v.add(grip, v.mul(axis, 3.2)), 0.8)
        sphere(v.add(grip, v.mul(axis, -3.6)), 2.5); sphere(v.add(grip, v.mul(axis, 3.6)), 2.5)
      } else if (p.kind === "bar") {
        capsule(v.add(grip, v.mul(across, -19)), v.add(grip, v.mul(across, 19)), 0.9)
        for (const s of [-1, 1]) {
          const c = v.add(grip, v.mul(across, 16 * s))
          blob(c, m === "side" ? [6.2, 6.2, 1.1] : [1.1, 6.2, 6.2])
        }
      } else if (p.kind === "ball") {
        sphere(weight, 4.8)
      }
    }
  }
  return out
}

// ── The camera, set once for a whole track ───────────────────────────────

export function camera(track, frames3) {
  const m = mode(track)
  const [az, el] = { side: [30, 11], front: [62, 11], plan: [28, 52] }[m].map((d) => (d * Math.PI) / 180)
  const c = [Math.sin(az) * Math.cos(el), Math.sin(el), Math.cos(az) * Math.cos(el)]
  const right = v.norm(v.cross([0, 1, 0], c))
  const up = v.cross(c, right)
  let x0 = 1e9, x1 = -1e9, y0 = 1e9, y1 = -1e9
  const see = (p, pad) => {
    const x = v.dot(p, right), y = v.dot(p, up)
    x0 = Math.min(x0, x - pad); x1 = Math.max(x1, x + pad); y0 = Math.min(y0, y - pad); y1 = Math.max(y1, y + pad)
  }
  for (const { J, things } of frames3) {
    for (const k in J) see(J[k], k === "head" ? 8 : 5.5)
    for (const t of things) {
      if (t.mat === MAT) continue
      if (t.type === 1) for (const sx of [-1, 1]) for (const sy of [-1, 1]) for (const sz of [-1, 1]) see(v.add(t.a, [t.b[0] * sx, t.b[1] * sy, t.b[2] * sz]), 0.5)
      else if (t.type === 3) see(t.a, Math.max(...t.b))
      else { see(t.a, t.r + 0.5); if (t.type === 0) see(t.b, t.r + 0.5) }
    }
  }
  // room round the figure, and always the floor it stands on
  const padX = 7, padTop = 7, padBottom = track.floor || m === "plan" ? 9 : 7
  x0 -= padX; x1 += padX; y1 += padTop; y0 -= padBottom
  let w = x1 - x0, hgt = y1 - y0
  const aspect = w / hgt > 1.12 ? 4 / 3 : 1
  if (w / hgt < aspect) { const need = hgt * aspect; x0 -= (need - w) / 2; x1 += (need - w) / 2; w = need }
  else { const need = w / aspect; y1 += need - hgt; hgt = need }
  const cx = (x0 + x1) / 2, cy = (y0 + y1) / 2
  return { c, right, up, center: v.add(v.mul(right, cx), v.mul(up, cy)), half: hgt / 2, aspect, floor: track.floor || m === "plan", water: waterLevel(track) }
}

function waterLevel(track) {
  const w = track.props.find((p) => p.kind === "block" && p.w > 100 && p.h <= 1.5)
  return w ? G - w.y : -1e4
}

// ── Drawing ──────────────────────────────────────────────────────────────

const NC = 28, NE = 48, NP = 28

const FRAG = `#version 300 es
precision highp float;
uniform vec2 uRes;
uniform vec3 uC, uR, uU, uCenter, uBg;
uniform float uHalf, uFloor, uWater, uK;
uniform vec4 uBound; // a sphere that holds everything drawn this frame
uniform int uNC, uNE, uNP;
uniform vec4 uCA[${NC}], uCB[${NC}], uCM[${NC}];
uniform vec4 uEC[${NE}], uER[${NE}];
uniform vec3 uEX[${NE}], uEY[${NE}];
uniform vec4 uPA[${NP}], uPB[${NP}], uPM[${NP}];
out vec4 o;

float dot2(vec3 a) { return dot(a, a); }

float sdRoundCone(vec3 p, vec3 a, vec3 b, float r1, float r2) {
  vec3 ba = b - a; float l2 = dot(ba, ba); float rr = r1 - r2; float a2 = l2 - rr * rr; float il2 = 1.0 / l2;
  vec3 pa = p - a; float y = dot(pa, ba); float z = y - l2;
  float x2 = dot2(pa * l2 - ba * y); float y2 = y * y * l2; float z2 = z * z * l2;
  float k = sign(rr) * rr * rr * x2;
  if (sign(z) * a2 * z2 > k) return sqrt(x2 + z2) * il2 - r2;
  if (sign(y) * a2 * y2 < k) return sqrt(x2 + y2) * il2 - r1;
  return (sqrt(x2 * a2 * il2) + y * rr) * il2 - r1;
}
float sdEllipsoid(vec3 p, vec3 r) { float k0 = length(p / r); float k1 = length(p / (r * r)); return k0 * (k0 - 1.0) / max(k1, 1e-4); }
float sdCapsule(vec3 p, vec3 a, vec3 b, float r) { vec3 pa = p - a, ba = b - a; float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0); return length(pa - ba * h) - r; }
float sdBox(vec3 p, vec3 b, float r) { vec3 q = abs(p) - b + r; return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0) - r; }
float smin(float a, float b, float k) { float h = max(k - abs(a - b), 0.0) / k; return min(a, b) - h * h * k * 0.25; }

// The body: every shape melted into its neighbours. hot is how much of the
// surface here belongs to a muscle that is being worked; mat is what the
// nearest shape is made of.
float body(vec3 p, out float hot, out float mat) {
  float d = 1e9, near = 1e9, hotNear = 1e9; mat = 0.0;
  for (int i = 0; i < uNC; i++) {
    float di = sdRoundCone(p, uCA[i].xyz, uCB[i].xyz, uCA[i].w, uCB[i].w);
    d = smin(d, di, uK);
    if (uCM[i].x > 0.5) hotNear = min(hotNear, di);
    if (di < near) { near = di; mat = uCM[i].y; }
  }
  for (int i = 0; i < uNE; i++) {
    vec3 q = p - uEC[i].xyz; vec3 ez = cross(uEX[i], uEY[i]);
    float di = sdEllipsoid(vec3(dot(q, uEX[i]), dot(q, uEY[i]), dot(q, ez)), uER[i].xyz);
    d = smin(d, di, uK);
    if (uEC[i].w > 0.5) hotNear = min(hotNear, di);
    if (di < near) { near = di; mat = uER[i].w; }
  }
  // How far under the skin the nearest worked muscle lies at this point.
  hot = 1.0 - smoothstep(0.35, 1.5, hotNear - d);
  return d;
}

float things(vec3 p, out float mat) {
  float d = 1e9; mat = 11.0;
  for (int i = 0; i < uNP; i++) {
    float di; int t = int(uPM[i].x);
    if (t == 0) di = sdCapsule(p, uPA[i].xyz, uPB[i].xyz, uPM[i].z);
    else if (t == 1) di = sdBox(p - uPA[i].xyz, uPB[i].xyz, uPM[i].z);
    else if (t == 2) di = length(p - uPA[i].xyz) - uPM[i].z;
    else di = sdEllipsoid(p - uPA[i].xyz, uPB[i].xyz);
    if (di < d) { d = di; mat = uPM[i].y; }
  }
  return d;
}

float scene(vec3 p, out float hot, out float mat) {
  float m2; float db = body(p, hot, mat); float dp = things(p, m2);
  if (dp < db) { hot = 0.0; mat = m2; return dp; }
  return db;
}
float sceneD(vec3 p) { float h, m; return scene(p, h, m); }

vec3 normal(vec3 p) {
  const vec2 e = vec2(1.0, -1.0) * 0.06;
  return normalize(e.xyy * sceneD(p + e.xyy) + e.yyx * sceneD(p + e.yyx) + e.yxy * sceneD(p + e.yxy) + e.xxx * sceneD(p + e.xxx));
}

bool misses(vec3 ro, vec3 rd) {
  vec3 oc = uBound.xyz - ro; float along = dot(oc, rd);
  return dot(oc, oc) - along * along > uBound.w * uBound.w;
}

float shadow(vec3 p, vec3 l, float k) {
  if (misses(p, l)) return 1.0;
  float res = 1.0, t = 0.6;
  for (int i = 0; i < 28; i++) {
    float h = sceneD(p + l * t);
    res = min(res, k * h / t);
    t += clamp(h, 0.35, 5.0);
    if (res < 0.01 || t > 90.0) break;
  }
  return clamp(res, 0.0, 1.0);
}

float occlusion(vec3 p, vec3 n) {
  float occ = 0.0, s = 1.0;
  for (int i = 1; i <= 5; i++) { float h = 0.5 * float(i) * 1.1; occ += (h - sceneD(p + n * h)) * s; s *= 0.62; }
  return clamp(1.0 - 0.28 * occ, 0.0, 1.0);
}

vec3 shade(vec2 px) {
  vec2 uv = (2.0 * px - uRes) / uRes.y;
  vec3 ro = uCenter + uR * (uv.x * uHalf) + uU * (uv.y * uHalf) + uC * 400.0;
  vec3 rd = -uC;
  vec3 key = normalize(-uR * 0.55 + uU * 0.75 + uC * 0.55);
  vec3 fill = normalize(uR * 0.8 + uU * 0.15 + uC * 0.4);

  float tFloor = uFloor > 0.5 && rd.y < -1e-4 ? -ro.y / rd.y : 1e9;
  float t = 250.0, tMax = min(tFloor, 620.0); bool hit = false; float hot = 0.0, mat = 0.0;
  if (misses(ro, rd)) t = tMax + 1.0;
  else t = max(t, dot(uBound.xyz - ro, rd) - uBound.w);
  float closest = 1e9;
  for (int i = 0; i < 110; i++) {
    if (t > tMax) break;
    float d = scene(ro + rd * t, hot, mat);
    closest = min(closest, d);
    if (d < 0.012) { hit = true; break; }
    t += d * 0.92;
    if (t > tMax) break;
  }
  float line = hit ? 0.0 : 1.0 - smoothstep(0.30, 0.52, closest);

  vec3 col;
  vec3 ink = uBg * 0.42;
  if (hit) {
    vec3 p = ro + rd * t; vec3 n = normal(p);
    vec3 base;
    if (mat < 0.5) base = vec3(0.83, 0.82, 0.80);          // the body
    else if (mat < 1.5) base = vec3(0.16, 0.20, 0.25);     // shorts
    else if (mat < 2.5) base = vec3(0.11, 0.13, 0.16);     // shoes
    else if (mat < 3.5) base = vec3(0.10, 0.11, 0.13);     // hair
    else if (mat < 10.5) base = vec3(0.17, 0.22, 0.27);    // the mat
    else if (mat < 11.5) base = vec3(0.36, 0.41, 0.47);    // equipment
    else base = vec3(0.93, 0.70, 0.22);                    // a band or cable
    float glow = hot;
    vec3 warm = vec3(1.0, 0.38, 0.13);
    base = mix(base, warm, glow * (mat < 0.5 ? 0.95 : 0.82));

    float occ = occlusion(p, n);
    float sh = shadow(p + n * 0.15, key, 9.0);
    // Three flat tones, as a figure is painted rather than lit: full light,
    // half tone, shadow, with a soft step between them.
    float lit = clamp(dot(n, key), 0.0, 1.0) * sh;
    float tone = 0.56 + 0.24 * smoothstep(0.03, 0.10, lit) + 0.20 * smoothstep(0.46, 0.56, lit);
    float fil = 0.5 + 0.5 * dot(n, fill);
    col = base * tone * mix(0.80, 1.0, occ);
    col += base * vec3(0.30, 0.42, 0.58) * 0.10 * fil * (1.0 - smoothstep(0.03, 0.10, lit));
    col += warm * glow * 0.10;
    // The line inside the figure: where a surface turns away from the eye.
    float turn = clamp(dot(n, -rd), 0.0, 1.0);
    col = mix(ink, col, smoothstep(0.10, 0.30, turn));
  } else if (tFloor < 1e8) {
    vec3 p = ro + rd * tFloor;
    float sh = shadow(p + vec3(0.0, 0.05, 0.0), key, 7.0);
    float near = length(p - uBound.xyz) > uBound.w + 7.0 ? 0.0 : clamp(1.0 - sceneD(p + vec3(0.0, 0.4, 0.0)) / 7.0, 0.0, 1.0);
    vec3 ground = uBg * 1.75 + 0.004;
    ground *= mix(1.0, 0.50, (1.0 - sh) * 0.9);
    ground *= 1.0 - 0.38 * near * near;
    float fade = smoothstep(1.02, 0.42, length(uv) * 0.8);
    col = mix(uBg, ground, fade);
  } else {
    col = uBg;
    // the surface of the water, when there is one: a soft band
    float wy = (ro + rd * 400.0).y - uWater;
    col += vec3(0.05, 0.10, 0.14) * exp(-wy * wy * 0.6);
  }
  col = mix(col, ink, line);
  return col;
}

void main() {
  vec3 col = shade(gl_FragCoord.xy);
  col = pow(max(col, 0.0), vec3(1.0 / 2.2));
  o = vec4(col, 1.0);
}`

const VERT = `#version 300 es
in vec2 p; void main() { gl_Position = vec4(p, 0.0, 1.0); }`

export function renderer(canvas) {
  const gl = canvas.getContext("webgl2", { preserveDrawingBuffer: true, antialias: false })
  const sh = (type, src) => {
    const s = gl.createShader(type); gl.shaderSource(s, src); gl.compileShader(s)
    if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(s))
    return s
  }
  const prog = gl.createProgram()
  gl.attachShader(prog, sh(gl.VERTEX_SHADER, VERT)); gl.attachShader(prog, sh(gl.FRAGMENT_SHADER, FRAG)); gl.linkProgram(prog)
  if (!gl.getProgramParameter(prog, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(prog))
  gl.useProgram(prog)
  const buf = gl.createBuffer(); gl.bindBuffer(gl.ARRAY_BUFFER, buf)
  gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW)
  gl.enableVertexAttribArray(0); gl.bindAttribLocation(prog, 0, "p"); gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 0, 0)
  const U = (n) => gl.getUniformLocation(prog, n)

  return function draw(cam, shapes, things, bg, bound) {
    gl.viewport(0, 0, canvas.width, canvas.height)
    gl.uniform2f(U("uRes"), canvas.width, canvas.height)
    gl.uniform3fv(U("uC"), cam.c); gl.uniform3fv(U("uR"), cam.right); gl.uniform3fv(U("uU"), cam.up)
    gl.uniform3fv(U("uCenter"), cam.center); gl.uniform3fv(U("uBg"), bg.map((c) => Math.pow(c, 2.2)))
    gl.uniform1f(U("uHalf"), cam.half); gl.uniform1f(U("uFloor"), cam.floor ? 1 : 0); gl.uniform1f(U("uWater"), cam.water)
    gl.uniform1f(U("uK"), 1.6)
    gl.uniform4fv(U("uBound"), bound)

    const { cones, ells } = shapes
    if (cones.length > NC || ells.length > NE || things.length > NP) throw new Error(`too many shapes: ${cones.length}/${ells.length}/${things.length}`)
    const ca = new Float32Array(NC * 4), cb = new Float32Array(NC * 4), cm = new Float32Array(NC * 4)
    cones.forEach((c, i) => { ca.set([...c.a, c.ra], i * 4); cb.set([...c.b, c.rb], i * 4); cm.set([c.hot, c.mat, 0, 0], i * 4) })
    gl.uniform1i(U("uNC"), cones.length); gl.uniform4fv(U("uCA"), ca); gl.uniform4fv(U("uCB"), cb); gl.uniform4fv(U("uCM"), cm)

    const ec = new Float32Array(NE * 4), er = new Float32Array(NE * 4), ex = new Float32Array(NE * 3), ey = new Float32Array(NE * 3)
    ells.forEach((e, i) => { ec.set([...e.c, e.hot], i * 4); er.set([...e.radii, e.mat], i * 4); ex.set(e.x, i * 3); ey.set(e.y, i * 3) })
    gl.uniform1i(U("uNE"), ells.length); gl.uniform4fv(U("uEC"), ec); gl.uniform4fv(U("uER"), er); gl.uniform3fv(U("uEX"), ex); gl.uniform3fv(U("uEY"), ey)

    const pa = new Float32Array(NP * 4), pb = new Float32Array(NP * 4), pm = new Float32Array(NP * 4)
    things.forEach((t, i) => { pa.set([...t.a, 0], i * 4); pb.set([...t.b, 0], i * 4); pm.set([t.type, t.mat, t.r, 0], i * 4) })
    gl.uniform1i(U("uNP"), things.length); gl.uniform4fv(U("uPA"), pa); gl.uniform4fv(U("uPB"), pb); gl.uniform4fv(U("uPM"), pm)

    gl.drawArrays(gl.TRIANGLES, 0, 3)
    gl.finish()
  }
}

// Everything a track needs before any frame is drawn: each frame in 3D, and
// one camera that holds the whole movement.
function bound(J, things) {
  const pts = Object.values(J).map((p) => [p, 7])
  for (const t of things) {
    if (t.type === 1) pts.push([t.a, Math.hypot(...t.b)])
    else if (t.type === 3) pts.push([t.a, Math.max(...t.b)])
    else { pts.push([t.a, t.r + 0.5]); if (t.type === 0) pts.push([t.b, t.r + 0.5]) }
  }
  const c = pts.reduce((acc, [p]) => v.add(acc, p), [0, 0, 0]).map((x) => x / pts.length)
  const r = Math.max(...pts.map(([p, pad]) => v.len(v.sub(p, c)) + pad))
  return [...c, r]
}

export function prepare(track, muscles) {
  const hot = new Set(muscles)
  const frames = track.frames.map((f, i) => {
    const J = lift(track, f)
    const things = gear(track, i, J)
    return { J, shapes: body(J, hot), things, bound: bound(J, things) }
  })
  return { frames, cam: camera(track, frames) }
}
