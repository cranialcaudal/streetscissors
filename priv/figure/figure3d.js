// The 3D figure: a body sculpted from a pose, with its muscles as separate
// volumes that can be lit.
//
// A track (Web.Fitness.Figure.track/2) is a list of frames, each the 2D
// joints of the figure on its stage. This file lifts a frame into 3D (the
// stage's plane, plus the width of a body), builds the body round the joints
// out of rounded cones and ellipsoids, and draws it by marching rays through
// their signed distance field. Nothing here is a mesh, and nothing is loaded:
// the figure is the same ninety-odd shapes in every clip, moved.
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
// How far from the middle of the body each hip joint, knee and ankle is. They
// were 4.8, 5.4 and 5.2, which set the hips a quarter wider than a man's
// (measure.mjs): the joints are 4 apart from the middle, and the legs come
// down from them all but straight.
const HIPS = 4.0, KNEES = 4.2, FEET = 4.4
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
    J.hip_a = at(f.hip_a, HIPS); J.hip_b = at(f.hip_b, -HIPS)
    // a stance wider than the hips takes the knees out after the feet and
    // turns the toes out a little, as a squat's does
    const wide = f.stance ?? FEET, out = Math.max(wide - FEET, 0)
    J.knee_a = at(f.knee_a, KNEES + out * 0.6); J.knee_b = at(f.knee_b, -KNEES - out * 0.6)
    J.foot_a = at(f.foot_a, wide); J.foot_b = at(f.foot_b, -wide)
    J.toe_a = at(f.toe_a, wide + 0.6 + out * 0.35); J.toe_b = at(f.toe_b, -wide - 0.6 - out * 0.35)
    J.hand_a = at(f.hand_a, gap + side); J.hand_b = at(f.hand_b, -gap + side)
    // The shoulder is not a fixed point on the trunk: it rises with an arm
    // reaching overhead and comes forward with one reaching out, the shoulder
    // blade turning under it. A little of each, by how far the arm reaches.
    const girdle = (S, H) => {
      const to = v.sub(H, S), far = Math.min(v.len(to) / (UPPER + FORE), 1), d = v.norm(to, [0, -1, 0])
      return v.add(S, [1.3 * Math.max(0, d[0]) * far, 1.2 * Math.max(0, d[1]) * far, 0])
    }
    J.sh_a = girdle(J.sh_a, J.hand_a); J.sh_b = girdle(J.sh_b, J.hand_b)
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
  if (m !== "side") {
    // a flat pose seen from the front has its hips 5 from the middle: bring
    // them (and the knees after them) in to a man's
    for (const k of ["a", "b"]) {
      const off = v.sub(J["hip_" + k], J.pelvis), far = v.len(off)
      if (far <= HIPS) continue
      const shift = v.mul(off, 1 - HIPS / far)
      J["hip_" + k] = v.sub(J["hip_" + k], shift)
      J["knee_" + k] = v.sub(J["knee_" + k], v.mul(shift, 0.9))
    }
  }
  return J
}

// ── The body round the joints ────────────────────────────────────────────

// The hand: how long the palm is from the wrist to the knuckles, and how far
// (in radians) the fingers turn at the knuckles when the hand is a fist.
const HAND_PALM = 3.3, HAND_FOLD = 2.6

export function body(J, hot, touch = {}) {
  const cones = [], ells = []
  // which of the body a shape belongs to ("trunk", "arm", "leg"): nothing
  // drawn reads it, but the tape takes the arms off to measure a chest
  let part = "trunk"
  const h = (muscle) => (muscle && hot.get(muscle)) || 0
  const cone = (a, b, ra, rb, muscle = null, mat = SKIN) => {
    if (v.len(v.sub(a, b)) < 0.05) b = v.add(b, [0, 0.05, 0])
    cones.push({ a, b, ra, rb, hot: h(muscle) + (muscle ? 2 : 0), mat, part })
  }
  // ax is the first axis, ay roughly the second; radii are along ax, ay and ax × ay
  const ell = (c, ax, ay, radii, muscle = null, mat = SKIN) => {
    const x = v.norm(ax, [1, 0, 0])
    const y = v.norm(v.reject(ay, x), v.norm(v.cross(x, [0.3, 0.2, 0.9])))
    ells.push({ c, x, y, radii, hot: h(muscle) + (muscle ? 2 : 0), mat, part })
  }

  const lat = v.norm(v.sub(J.sh_a, J.sh_b), [0, 0, 1])
  const latH = v.norm(v.sub(J.hip_a, J.hip_b), lat)
  const upLo = v.norm(v.sub(J.chest, J.pelvis))
  const upUp = v.norm(v.sub(J.neck, J.chest), upLo)
  const frLo = v.norm(v.cross(upLo, latH), [1, 0, 0])
  const frUp = v.norm(v.cross(upUp, lat), frLo)
  const P = (base, ...terms) => terms.reduce((acc, [dir, k]) => v.add(acc, v.mul(dir, k)), base)

  // ── How the whole body is built: bone, then muscle, then skin ───────────
  //
  // Bone is rigid and comes first: it is thin, and it is what the pose moves.
  // A muscle is laid from where it starts on one bone to where it ends on
  // another, so it follows the joint between them; and it keeps its volume,
  // so it thins where a bent joint draws it out and thickens where one
  // bunches it. The skin is only the melting of all of these together. Three
  // helpers say it:
  const dist = (a, b) => v.len(v.sub(a, b))
  // how much thicker (or thinner) a belly is at the length it is posed at
  // than at `rest`, its length with the joint straight
  const swell = (rest, now) => Math.min(1.32, Math.max(0.8, Math.sqrt(rest / Math.max(now, rest * 0.45))))
  // the length of a muscle that runs over the outside of a joint, round `via`
  const round = (o, via, i) => dist(o, via) + dist(via, i)
  // a belly lying from `o` to `i`: `thick` is its half-thickness along
  // `face`, `wide` its half-width square to both
  const belly = (o, i, face, wide, thick, muscle, mat = SKIN, cover = 0.5, at = 0.5) => {
    const span = v.sub(i, o)
    ell(v.mix(o, i, at), span, v.cross(face, span), [v.len(span) * cover + 1.0, wide, thick], muscle, mat)
  }

  // The trunk below the ribs, laid out by measurement (measure.mjs). The
  // pelvis is a tall basin: the hip joints are near its floor, the crotch is
  // only a little below them, and its crests are as high as the navel. So
  // the hips are widest at the joints and narrow upward to the crests, and
  // the waist is no more than the short gap between the crests and the
  // lowest ribs. A pelvis drawn as a ball round the hip joints put the
  // crotch a hand too low, the waist a hand too low, and a shelf between.
  //
  // Between the basin and the cage there is no bone but the spine: the belly
  // is held in by muscle alone. A wall down the front from the ribs to the
  // pubic bone, which bends the trunk and so shortens and thickens as it
  // curls; a sheet at each side from the ribs to the crest of the hip; and a
  // column either side of the spine from the sacrum up the back. Each lies
  // almost flush, or the belly reads as flaps.
  const waist = v.mix(J.pelvis, J.chest, 0.62)
  const rib = v.mix(J.chest, J.neck, 0.4)
  ell(P(J.pelvis, [upLo, 2.3]), frLo, upLo, [4.3, 4.6, 6.0], null, SHORTS)
  // the crotch of the shorts, which hangs a little below the body's own
  ell(P(J.pelvis, [upLo, -2.0]), frLo, upLo, [3.4, 1.6, 2.6], null, SHORTS)
  ell(waist, frLo, upLo, [4.2, 7.6, 5.9])
  const ribsFront = P(rib, [upUp, -4.6], [frUp, 3.3]), pubis = P(J.pelvis, [frLo, 1.6], [upLo, 1.6])
  const absRest = dist(J.chest, J.pelvis) + 0.4 * dist(J.neck, J.chest) - 6.2
  belly(ribsFront, pubis, frLo, 3.9, 2.2 * swell(absRest, dist(ribsFront, pubis)), "abs")
  for (const s of [1, -1]) {
    // the crest of the hip, which the side of the waist comes down to
    ell(P(J.pelvis, [latH, 4.9 * s], [upLo, 5.4], [frLo, -0.2]), frLo, upLo, [3.6, 2.6, 1.9])
    belly(P(rib, [upUp, -4.6], [frUp, 0.4], [lat, 4.8 * s]), P(J.pelvis, [upLo, 6.4], [frLo, 0.3], [latH, 5.0 * s]), v.mul(latH, s), 2.8, 1.9, "obliques")
    belly(P(J.pelvis, [frLo, -2.5], [upLo, 3.0], [latH, 1.7 * s]), P(rib, [upUp, -2.0], [frUp, -3.1], [lat, 1.8 * s]), v.mul(frLo, -1), 1.9, 2.0, "lowback")
  }

  // Where the arm hangs from. The pose engine puts the shoulder joint level
  // with the root of the neck, which is three units higher than a man's is
  // at rest (measure.mjs) and about right with the arm overhead. Drawn there
  // the figure shrugged. So the arm is hung a little lower while it is down
  // and from the pose's point once it is raised, as a shoulder blade carries
  // a shoulder. It is a correction to the drawing only: the elbow stays
  // where the pose has it, so the upper arm is drawn a tenth short while it
  // hangs. Lowering the joint in the engine would mean reaching every pose
  // again.
  const socket = (S, E) => {
    const up = v.dot(v.norm(v.sub(E, S), v.mul(upUp, -1)), upUp)
    const raised = Math.min(Math.max((up + 0.3) / 1.2, 0), 1)
    return P(S, [upUp, -1.4 * (1 - raised * raised * (3 - 2 * raised))])
  }

  // The chest, built the way a body is: bone, then muscle, then skin.
  //
  // The rib cage is an egg, narrower than the shoulders and deeper below than
  // above, and nothing on it moves. The shoulders hang off it on the collar
  // bones, struts from the top of the breastbone, and the shoulder blades ride
  // on its back. The muscles that give a chest its shape do not belong to the
  // cage at all: the pectoral in front and the lat behind each run from the
  // trunk to the upper arm. So with the arm down they lie across the chest,
  // and with the arm raised they are drawn out toward it and make the two
  // folds of the armpit. A pectoral that stays put when the arm moves, on a
  // cage as wide as the shoulders, was what made this "the worst part".
  ell(rib, frUp, upUp, [5.0, 9.4, 6.5])
  // the lower ribs, where a cage is widest
  ell(P(J.chest, [upUp, 2.2]), frUp, upUp, [4.6, 5.2, 6.8])
  ell(P(J.neck, [upUp, -3.2], [frUp, -0.2]), frUp, upUp, [4.2, 3.6, 6.6])
  const notch = P(J.neck, [frUp, 2.6], [upUp, -1.8])
  for (const [s, at, E] of [[1, J.sh_a, J.elbow_a], [-1, J.sh_b, J.elbow_b]]) {
    const S = socket(at, E)
    const arm = v.norm(v.sub(E, S), [0, -1, 0])
    // the collar bone, and the shoulder blade behind it
    cone(notch, P(S, [upUp, 0.5], [frUp, 0.5]), 1.0, 0.95)
    ell(P(S, [lat, -3.4 * s], [frUp, -2.7], [upUp, -2.6]), frUp, upUp, [1.3, 3.9, 2.9])
    // the pectoral: breastbone and collar bone to the upper arm
    const from = P(rib, [upUp, 2.2], [frUp, 3.9], [lat, 2.3 * s]), to = P(S, [arm, 3.2], [frUp, 0.8])
    const span = v.sub(to, from)
    ell(v.mix(from, to, 0.44), span, v.cross(frUp, span), [v.len(span) * 0.5 + 1.3, 3.4, 1.8], "chest")
    // the lat: the small of the back to the upper arm, behind the armpit
    cone(P(waist, [frLo, -2.3], [latH, 3.4 * s]), P(S, [arm, 2.6], [frUp, -1.6], [lat, -1.2 * s]), 2.9, 2.0, "lats")
    ell(P(rib, [upUp, -3.2], [frUp, 1.4], [lat, 5.4 * s]), frUp, upUp, [2.4, 3.6, 1.5], "serratus")
  }
  ell(P(J.neck, [frUp, -2.0], [upUp, -2.4]), frUp, upUp, [2.5, 4.8, 5.0], "traps")
  // between the shoulder blades
  ell(P(rib, [upUp, 1.4], [frUp, -3.6]), frUp, upUp, [1.5, 4.4, 4.0], "rhomboids")

  // neck and head
  const crown = v.norm(v.sub(J.head, J.nape), upUp)
  const face = v.norm(v.reject(frUp, crown), frUp)
  const ear = v.norm(v.cross(crown, face), lat)
  // The neck is the column of the spine with the deep muscles round it, and
  // in front of it the two straps from behind each ear to the top of the
  // breastbone, which turn and nod the head and make the V of the throat.
  cone(P(J.neck, [upUp, -1.2]), P(J.nape, [crown, 1.8]), 2.6, 2.3, "neck")
  // The head is a ball, and the face is drawn on it (see `face` in the
  // shader): the author's own drawing of a head, a circle with four strokes,
  // traced. No skull, jaw, nose, brow, ears or hair: the strokes say which
  // way the head is turned, which is what a face is for on a figure this
  // size. A ball as long as a man's head is a third broader than one, and
  // that is the drawing's doing, not a fault for the tape.
  const HEAD = 4.7
  const ball = P(J.head, [crown, -0.6])
  ell(ball, face, crown, [HEAD, HEAD, HEAD])
  for (const s of [1, -1]) cone(P(ball, [ear, 2.6 * s], [crown, -2.6], [face, -0.8]), P(notch, [lat, 0.9 * s], [frUp, -0.5]), 0.85, 0.8, "neck")

  // A hand without fingers: two plates, the palm and the fingers as one, hinged
  // at the knuckles, on a wrist that is a joint of its own. `dir` is the way
  // the palm runs from the wrist `W`, `back` the way the back of the hand
  // faces, `curl` how far the fingers are folded toward the palm (0 laid
  // flat, 1 a fist), `s` which hand, for the side the thumb is on.
  const hand = (W, dir, back, curl, s) => {
    const side = v.norm(v.cross(dir, back), [0, 0, 1])
    ell(P(W, [dir, 0.6]), dir, back, [0.9, 0.85, 1.3])
    ell(P(W, [dir, HAND_PALM * 0.52]), dir, back, [HAND_PALM * 0.58, 0.85, 1.9])
    const knuckles = P(W, [dir, HAND_PALM])
    const fold = curl * HAND_FOLD
    const along = v.norm(v.add(v.mul(dir, Math.cos(fold)), v.mul(back, -Math.sin(fold))), dir)
    const over = v.norm(v.add(v.mul(back, Math.cos(fold)), v.mul(dir, Math.sin(fold))), back)
    const long = 1.55 - 0.45 * curl
    ell(P(knuckles, [along, long * 0.9], [back, -0.15 * curl]), along, over, [long + 0.35, 0.75 + 0.25 * curl, 1.8])
    // the thumb lies along the palm's edge, and across the fingers as they close
    ell(P(W, [dir, 1.5 + 0.6 * curl], [side, 1.75 * s * (1 - 0.35 * curl)], [back, -0.5 * curl]), dir, back, [1.45, 0.7, 0.75])
  }

  // arms
  part = "arm"
  for (const [s, at, E, H] of [[1, J.sh_a, J.elbow_a, J.hand_a], [-1, J.sh_b, J.elbow_b, J.hand_b]]) {
    const S = socket(at, E)
    const along = v.norm(v.sub(E, S), [0, -1, 0])
    // the trapezius down to the point of the shoulder, and the deltoid, from
    // the point of the shoulder down the arm it lifts: with the arm raised it
    // has shortened, and stands up over the joint
    cone(v.mix(J.nape, J.neck, 0.5), P(S, [upUp, 0.6]), 2.1, 1.5, "traps")
    const delt = 1 + 0.4 * (swell(7.2, dist(P(S, [lat, 1.5 * s], [upUp, 1.5]), P(S, [along, 5.5]))) - 1)
    ell(P(S, [along, 2.4], [lat, 0.5 * s]), along, lat, [3.9, 3.0 * delt, 3.1 * delt], "delts")
    let fr = v.reject(v.sub(H, E), along)
    fr = v.len(fr) < 0.8 ? v.norm(v.reject(frUp, along), [1, 0, 0]) : v.norm(fr)
    // The arm bone is thin; the arm's shape is the two muscles on it. The one
    // in front bends the elbow, so it shortens and stands up as the elbow
    // bends. The one behind straightens it and runs round the back of the
    // joint to the point of the elbow, so a bent elbow draws it out.
    cone(S, E, 2.0, 1.5)
    ell(E, along, fr, [1.7, 1.4, 1.85])
    const reachDir = v.norm(v.sub(H, E), along)
    const biFrom = P(S, [fr, 1.2], [along, 1.0]), biTo = P(v.mix(E, H, 0.16), [fr, 0.4])
    const biceps = swell(dist(biFrom, E) + dist(E, biTo), dist(biFrom, biTo))
    ell(P(v.mix(S, E, 0.56 - 0.1 * (biceps - 1)), [fr, 0.7]), along, fr, [5.2 / biceps, 1.85 * biceps, 2.0], "biceps")
    const triFrom = P(S, [fr, -1.2], [along, 1.2]), triTo = P(v.mix(E, H, 0.08), [fr, -1.0])
    const triceps = swell(dist(triFrom, E) + dist(E, triTo), round(triFrom, P(E, [fr, -2.0]), triTo))
    ell(P(v.mix(S, E, 0.5), [fr, -0.8]), along, fr, [5.8, 1.88 * triceps, 2.05], "triceps")
    // the forearm: two bones, the muscles that work the wrist and the grip
    // thick below the elbow, and nothing but tendon at the wrist (so the
    // bones are not lit with the muscle, nor sunk with it: sunk, the wrist
    // was three quarters of a man's)
    // The pose's hand point is the middle of a fist, whether the fist holds
    // a bar or nothing, so the wrist is short of it: a forearm is 12 or 13
    // long and a fist's middle 2 or 3 beyond. Only a palm laid flat has its
    // wrist at the point itself, and there the forearm is drawn a fifth too
    // long.
    const did = touch[s === 1 ? "hand_a" : "hand_b"]
    const wrist = did && did.flat ? H : P(H, [reachDir, did && did.grip ? -2.1 : -2.1])
    cone(E, wrist, 1.5, 1.15)
    ell(v.mix(E, H, 0.31), reachDir, fr, [5.2, 2.3, 2.1], "forearms")
    // the point of the elbow, behind the joint
    ell(P(E, [fr, -0.35]), along, fr, [1.5, 0.95, 1.5])
    if (did && did.grip) {
      // a fist: the fingers rolled round what is held, the thumb closing it
      const bar = did.grip
      const back = v.norm(v.reject(reachDir, bar), fr)
      ell(H, bar, back, [2.15, 1.75, 1.75])
      ell(P(H, [back, 1.0]), bar, back, [2.0, 1.0, 1.9])
      ell(P(H, [back, -0.9], [bar, 1.5 * s]), back, bar, [1.5, 0.75, 0.8])
      ell(P(H, [back, -1.5]), reachDir, bar, [1.5, 1.7, 1.25])
    } else if (did && did.flat) {
      // A palm laid on what it rests on, the wrist bent back as far as the
      // forearm stands over it. On something round (a ball, a dome, a bell)
      // the fingers fold at the knuckles to follow it.
      const n = did.flat
      let ahead = v.reject(reachDir, n)
      ahead = v.len(ahead) < 0.35 ? v.norm(v.reject(frUp, n), [1, 0, 0]) : v.norm(ahead)
      const wrap = did.round ? Math.min(HAND_PALM / did.round, 1.1) / HAND_FOLD : 0
      hand(P(did.at, [ahead, -0.3], [n, 0.95]), ahead, n, wrap, s)
    } else if (!touch.open) {
      // A hand with nothing in it is a loose fist: a runner's, a boxer's. Laid
      // open it read as a blade, and a punch as a slap. Its wrist is slack:
      // held out level, the hand hangs a little from it.
      const slack = Math.max(0, 1 - Math.abs(reachDir[1])) * 0.24
      const dir = v.norm(v.add(reachDir, [0, -slack, 0]), reachDir)
      hand(wrist, dir, v.norm(v.reject(v.mul(fr, -1), dir), v.mul(fr, -1)), 0.8, s)
    } else {
      // an open hand, for a swimmer: the fingers a little curled
      hand(wrist, reachDir, v.mul(fr, -1), 0.1, s)
    }
  }

  // legs
  part = "leg"
  for (const [s, Hp, K, A, T] of [[1, J.hip_a, J.knee_a, J.foot_a, J.toe_a], [-1, J.hip_b, J.knee_b, J.foot_b, J.toe_b]]) {
    const along = v.norm(v.sub(K, Hp), [0, -1, 0])
    let fr = v.reject(v.sub(K, v.mix(Hp, A, 0.5)), v.norm(v.sub(A, Hp), along))
    fr = v.len(fr) < 0.8 ? v.norm(v.reject(frLo, along), [1, 0, 0]) : v.norm(v.reject(fr, along), frLo)
    const inner = v.mul(latH, -s)
    const shin = v.norm(v.sub(A, K), along)
    const frS = v.norm(v.reject(fr, shin), fr)
    const toe = v.norm(v.sub(T, A), [1, 0, 0])
    // The thigh bone, the knee, the shin bone, the ankle. Then the muscles,
    // each from one bone to another.
    cone(Hp, K, 3.1, 2.4)
    // The leg of the shorts: two tubes, one before the other, so that it is
    // deeper than it is wide as the top of a thigh is, stands clear of the
    // other leg, and ends in a hem.
    const hem = v.mix(Hp, K, 0.38)
    for (const f of [1.5, -1.4]) cone(P(Hp, [fr, f], [inner, -0.2]), P(hem, [fr, f * 0.95], [inner, -0.2]), 3.25, 3.15, null, SHORTS)
    ell(K, along, fr, [2.3, 2.2, 2.4])
    ell(P(K, [fr, 1.3]), along, fr, [1.8, 1.2, 1.6])
    cone(K, A, 2.2, 1.5)
    ell(A, shin, frS, [1.8, 1.6, 2.1])

    // The seat: from the back of the pelvis to the back of the thigh bone,
    // round the back of the hip. It straightens the hip, so a deep squat
    // draws it out under the joint.
    const seat = P(J.pelvis, [latH, 2.8 * s], [frLo, -2.7], [upLo, 4.6])
    const seatTo = P(v.mix(Hp, K, 0.2), [fr, -1.6], [inner, -0.8])
    const glute = swell(dist(seat, Hp) + dist(Hp, seatTo), round(seat, P(Hp, [frLo, -3.6]), seatTo))
    belly(seat, seatTo, v.mul(frLo, -1), 3.2, 3.7 * glute, "glutes", SHORTS, 0.5, 0.45)
    // the side of the hip, which holds the pelvis level on one leg, and the
    // crease in front, which lifts the thigh
    belly(P(J.pelvis, [latH, 5.4 * s], [upLo, 4.4]), P(Hp, [latH, 2.2 * s], [along, 1.2]), v.mul(latH, s), 2.6, 1.3, "abductors", SHORTS)
    const crease = P(J.pelvis, [latH, 3.2 * s], [frLo, 2.6], [upLo, 3.6]), creaseTo = P(v.mix(Hp, K, 0.14), [fr, 1.6])
    belly(crease, creaseTo, frLo, 2.2, 1.6 * swell(dist(crease, Hp) + dist(Hp, creaseTo), dist(crease, creaseTo)), "hipflexors", SHORTS)

    // The front of the thigh straightens the knee: it runs over the kneecap
    // to the shin, so a bent knee draws it out. The back of the thigh bends
    // the knee and runs from the sit bone, so it bunches as the knee bends
    // and is drawn out when the hips fold over straight legs.
    const quadFrom = P(Hp, [fr, 1.4], [along, 1.0]), quadTo = P(v.mix(K, A, 0.12), [frS, 1.3])
    const quads = swell(dist(quadFrom, K) + dist(K, quadTo), round(quadFrom, P(K, [fr, 2.4]), quadTo))
    ell(P(v.mix(Hp, K, 0.46), [fr, 1.5]), along, fr, [8.4, 3.0 * quads, 3.4], "quads")
    const sit = P(Hp, [frLo, -2.2], [upLo, -1.4]), hamTo = P(v.mix(K, A, 0.1), [frS, -1.3])
    const hams = swell(dist(sit, K) + dist(K, hamTo), dist(sit, hamTo))
    ell(P(v.mix(Hp, K, 0.48), [fr, -1.5]), along, fr, [8.0, 2.8 * hams, 3.3], "hamstrings")
    belly(P(Hp, [inner, 2.0], [frLo, 0.6], [upLo, -1.4]), P(v.mix(Hp, K, 0.58), [inner, 0.7]), inner, 2.4, 1.6, "adductors")

    // The calf runs from above the knee to the heel, and points the foot: up
    // on the toes it shortens and stands out. The muscle down the front of
    // the shin lifts the foot.
    const calfFrom = P(v.mix(Hp, K, 0.94), [fr, -1.4])
    const calf = swell(dist(calfFrom, P(A, [frS, -1.8])), dist(calfFrom, P(A, [toe, -1.8])))
    ell(P(v.mix(K, A, 0.28), [frS, -1.0]), shin, frS, [5.4, 2.35 * calf, 2.5], "calves")
    const shinFrom = P(v.mix(K, A, 0.1), [frS, 0.9])
    const front = swell(dist(shinFrom, P(A, [frS, 2.2])), dist(shinFrom, P(A, [toe, 2.2])))
    ell(P(v.mix(K, A, 0.36), [frS, 0.95]), shin, frS, [5.0, 1.5 * front, 1.6], "tibialis")
    // a shoe: a long low toe box and a heel, flat underneath
    const sole = v.norm(v.reject(shin, toe), [0, -1, 0])
    if (T[1] < 3.6 && A[1] - T[1] > 1.4) {
      // Up on the ball of the foot (a push-up, the back foot of a lunge, the
      // top of a calf raise): the toes stay flat on the floor and the rest of
      // the foot rises from where they begin. A rigid shoe stood on its tip.
      const flat = v.norm([toe[0], 0, toe[2]], [1, 0, 0])
      const ball = v.add(T, v.mul(flat, -2.6))
      const rear = v.norm(v.sub(ball, A), toe)
      const under = v.norm(v.reject([0, -1, 0], rear), sole)
      ell(P(v.mix(ball, T, 0.5), [[0, 1, 0], 0.5]), flat, [0, 1, 0], [2.3, 1.25, 2.3], null, SHOES)
      ell(P(v.mix(A, ball, 0.55), [under, 0.4]), rear, under, [v.len(v.sub(ball, A)) * 0.5 + 1.3, 1.7, 2.25], null, SHOES)
      ell(P(A, [rear, -0.8], [under, 0.2]), rear, under, [2.4, 2.0, 2.1], null, SHOES)
    } else {
      ell(P(v.mix(A, T, 0.55), [sole, 0.5]), toe, sole, [4.8, 1.7, 2.3], null, SHOES)
      ell(P(A, [toe, -0.8], [sole, 0.2]), toe, sole, [2.5, 2.1, 2.1], null, SHOES)
    }
  }
  return { cones, ells, head: { at: ball, r: HEAD, face, crown } }
}

// ── The same solid, without a picture ────────────────────────────────────

// How the shapes are joined into one surface: a muscle is sunk SINK under the
// skin and melted into it over MELT, and every other shape melts into its
// neighbour over BLEND. The shader is given these same three numbers.
export const FIELD = { SINK: 0.4, MELT: 1.9, BLEND: 1.2 }

// The distance from a point to the body's surface (negative inside), worked
// out as the shader's body() works it out. Nothing that draws uses this: it
// is for tools that put a tape round the figure (measure.mjs). Keep the two
// in step.
export function solid({ cones, ells }) {
  const smin = (a, b, k) => {
    const h = Math.max(k - Math.abs(a - b), 0) / k
    return Math.min(a, b) - h * h * k * 0.25
  }
  const roundCone = (p, { a, b, ra, rb }) => {
    const ba = v.sub(b, a), l2 = v.dot(ba, ba), rr = ra - rb, a2 = l2 - rr * rr, il2 = 1 / l2
    const pa = v.sub(p, a), y = v.dot(pa, ba), z = y - l2
    const w = v.sub(v.mul(pa, l2), v.mul(ba, y)), x2 = v.dot(w, w), y2 = y * y * l2, z2 = z * z * l2
    const k = Math.sign(rr) * rr * rr * x2
    if (Math.sign(z) * a2 * z2 > k) return Math.sqrt(x2 + z2) * il2 - rb
    if (Math.sign(y) * a2 * y2 < k) return Math.sqrt(x2 + y2) * il2 - ra
    return (Math.sqrt(x2 * a2 * il2) + y * rr) * il2 - ra
  }
  const third = new Map(ells.map((e) => [e, v.cross(e.x, e.y)]))
  const ellipsoid = (p, e) => {
    const { c, x, y, radii } = e, z = third.get(e)
    const qx = p[0] - c[0], qy = p[1] - c[1], qz = p[2] - c[2]
    const a = (qx * x[0] + qy * x[1] + qz * x[2]) / radii[0], b = (qx * y[0] + qy * y[1] + qz * y[2]) / radii[1]
    const g = (qx * z[0] + qy * z[1] + qz * z[2]) / radii[2]
    const k0 = Math.hypot(a, b, g), k1 = Math.hypot(a / radii[0], b / radii[1], g / radii[2])
    return (k0 * (k0 - 1)) / Math.max(k1, 1e-4)
  }
  const join = (d, di, muscle) => smin(d, muscle ? di + FIELD.SINK : di, muscle ? FIELD.MELT : FIELD.BLEND)
  return (p) => {
    let d = 1e9
    for (const c of cones) d = join(d, roundCone(p, c), c.hot > 1.5)
    for (const e of ells) d = join(d, ellipsoid(p, e), e.hot > 1.5)
    return d
  }
}

// ── What a hand is doing ─────────────────────────────────────────────────

// A hand is a fist round whatever bar, handle or band passes through it, a
// flat palm on whatever it rests on (the floor, a box, a wall, a ball), and
// open otherwise. Which it is is read off the things beside it, so a figure
// file never has to say. Returns {grip: axis}, {flat: normal, at: point on
// the surface} or null.
function touching(H, things, track) {
  let best = null, near = 1.6
  const take = (d, what) => { if (d < near) { near = d; best = what } }
  for (const t of things) {
    if (t.type === 0) {
      const ab = v.sub(t.b, t.a), len2 = ab[0] * ab[0] + ab[1] * ab[1] + ab[2] * ab[2]
      const k = len2 < 1e-6 ? 0 : Math.max(0, Math.min(1, v.sub(H, t.a).reduce((acc, x, i) => acc + x * ab[i], 0) / len2))
      const q = v.add(t.a, v.mul(ab, k))
      // a band ends in the hand; a bar or a handle passes through it
      take(v.len(v.sub(H, q)) - t.r - 0.6, { grip: v.norm(ab, [0, 0, 1]) })
    } else if (t.type === 1) {
      const q = v.sub(H, t.a), half = t.b
      const out = q.map((x, i) => Math.abs(x) - half[i])
      const axis = out.indexOf(Math.max(...out))
      if (out.every((o, i) => i === axis || o < 1.0)) {
        const n = [0, 0, 0]; n[axis] = Math.sign(q[axis]) || 1
        const at = H.slice(); at[axis] = t.a[axis] + n[axis] * half[axis]
        take(Math.abs(out[axis]) - 0.6, { flat: n, at })
      }
    } else if (t.type === 2) {
      const n = v.norm(v.sub(H, t.a), [0, 1, 0])
      take(Math.abs(v.len(v.sub(H, t.a)) - t.r) - 0.8, { flat: n, at: v.add(t.a, v.mul(n, t.r)), round: t.r })
    } else {
      // a dome: the point of it under the hand, and the way its surface faces there
      const q = v.sub(H, t.a)
      const k = 1 / Math.max(Math.hypot(q[0] / t.b[0], q[1] / t.b[1], q[2] / t.b[2]), 1e-6)
      const at = v.add(t.a, v.mul(q, k))
      const n = v.norm([q[0] / (t.b[0] * t.b[0]), q[1] / (t.b[1] * t.b[1]), q[2] / (t.b[2] * t.b[2])], [0, 1, 0])
      take(Math.abs(v.len(q) * (1 - k)) - 0.8, { flat: n, at, round: Math.max(...t.b) * 1.5 })
    }
  }
  if (!best && (track.floor || mode(track) === "plan") && H[1] < 2.6 && mode(track) !== "plan") best = { flat: [0, 1, 0], at: [H[0], 0, H[2]] }
  return best
}

// ── What is held, stood on or pulled ─────────────────────────────────────

// A kettlebell: the bell's radius, half the width of its grip, and how far
// the middle of the bell hangs from the middle of the grip.
const KB_BELL = 4.0, KB_GRIP = 2.9, KB_REACH = 7.4

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
        // A bell with a handle a hand closes round: the grip a bar wider than
        // the fist, a horn down from each end of it to the bell's shoulders,
        // and a window between the bar and the bell for the fingers. The bell
        // used to begin under the bar, so the hand was drawn sunk in the iron.
        const down = v.norm(v.sub(weight, grip), [0, -1, 0])
        const bell = v.add(grip, v.mul(down, KB_REACH))
        const a = v.add(grip, v.mul(across, -KB_GRIP)), b = v.add(grip, v.mul(across, KB_GRIP))
        capsule(a, b, 0.72)
        const shoulder = v.add(bell, v.mul(down, -KB_BELL * 0.66))
        capsule(a, v.add(shoulder, v.mul(across, -KB_BELL * 0.62)), 0.72)
        capsule(b, v.add(shoulder, v.mul(across, KB_BELL * 0.62)), 0.72)
        sphere(bell, KB_BELL)
      } else if (p.kind === "dumbbell") {
        // The handle lies across the palm, so it is square to the forearm: a
        // dumbbell curled to the shoulder turns with the hand, it does not
        // stay level. Held across, it runs from side to side (a curl, a
        // press); held neutral, front to back (a hammer curl, a row, a carry).
        const E = p.hold === "hand_a" ? J.elbow_a : p.hold === "hand_b" ? J.elbow_b : null
        const fore = E ? v.norm(v.sub(hand, E), [0, -1, 0]) : [0, -1, 0]
        const flat = m === "side" ? [1, 0, 0] : [0, 0, 1]
        const axis = p.grip === "across" ? v.norm(v.reject(across, fore), across) : v.norm(v.cross(fore, across), flat)
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

const NC = 28, NE = 84, NP = 28
const BANDS = 16 // how many pieces a frame is drawn in: see draw()

const FRAG = `#version 300 es
precision highp float;
uniform vec2 uRes;
uniform vec3 uC, uR, uU, uCenter, uBg;
uniform float uHalf, uFloor, uWater, uK;
uniform vec4 uBound; // a sphere that holds everything drawn this frame
uniform vec4 uHead;  // the head's ball: its middle and its radius
uniform vec3 uHeadF, uHeadU; // the way the face looks, and the way the crown points
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
// A muscle lies under the skin, not on it: its shape is sunk a little and
// melted into the form it belongs to, so it shapes the surface without
// standing off it as a lump of its own. How far is a matter of taste that
// has gone both ways: at 0 and 1.6 (the body's own blend) he was "too lumpy";
// at 0.7 and 3.2 every form ran into the next. "No more smooth than round":
// each form reads as a round thing of its own, with an edge where it meets
// its neighbour. The lit area's edge is as hard as the tones' for the same
// reason.
const float SINK = ${FIELD.SINK.toFixed(2)}, MELT = ${FIELD.MELT.toFixed(2)};
vec3 tier(vec3 lit, float level, float di) {
  if (level > 0.75) lit.x = min(lit.x, di);
  else if (level > 0.35) lit.y = min(lit.y, di);
  else if (level > 0.1) lit.z = min(lit.z, di);
  return lit;
}
float body(vec3 p, out float hot, out float mat) {
  float d = 1e9, near = 1e9; mat = 0.0;
  // how near the surface a worked muscle lies, for each of the three tiers
  vec3 lit = vec3(1e9);
  for (int i = 0; i < uNC; i++) {
    float di = sdRoundCone(p, uCA[i].xyz, uCB[i].xyz, uCA[i].w, uCB[i].w);
    bool mus = uCM[i].x > 1.5;
    d = smin(d, mus ? di + SINK : di, mus ? MELT : uK);
    lit = tier(lit, mus ? uCM[i].x - 2.0 : uCM[i].x, di);
    if (di < near) { near = di; mat = uCM[i].y; }
  }
  for (int i = 0; i < uNE; i++) {
    vec3 q = p - uEC[i].xyz; vec3 ez = cross(uEX[i], uEY[i]);
    float di = sdEllipsoid(vec3(dot(q, uEX[i]), dot(q, uEY[i]), dot(q, ez)), uER[i].xyz);
    bool mus = uEC[i].w > 1.5;
    d = smin(d, mus ? di + SINK : di, mus ? MELT : uK);
    lit = tier(lit, mus ? uEC[i].w - 2.0 : uEC[i].w, di);
    if (di < near) { near = di; mat = uER[i].w; }
  }
  // How far under the skin the nearest worked muscle lies at this point.
  vec3 glow = 1.0 - smoothstep(0.45 + SINK, 0.85 + SINK, lit - d);
  // the mover at full strength, the chain that steadies it at half, the
  // bracing of the rest of the body as a trace
  hot = max(glow.x, max(glow.y * 0.5, glow.z * 0.22));
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

// The face: the author's drawing of a head, traced on to the ball. A circle
// with four strokes. A line from the crown down the middle of the face,
// stopping short of the chin. Two arcs that start together at one temple
// and end together at the other, the upper bowed up over the brow and the
// lower all but straight, so that from the front they make a lens. A short
// stroke across the middle line, low down.
//
// Each stroke is where a plane cuts the ball, so it turns with the head and
// is seen from the side as a drawing of a head is. The drawing was made
// looking straight at the head and the camera looks down on a standing figure
// by 11 degrees, so the strokes are laid on 11 degrees higher than they were
// drawn: seen from the camera they are where the pencil put them.
//
// Heights are shares of the ball's radius above its middle. FACE_TEMPLE is
// where the two arcs meet; FACE_BROW and FACE_EYE are how far each arc's
// plane is tipped up toward the front, in radians; FACE_CHIN is where the
// middle line stops; FACE_MOUTH is the short stroke's height and
// FACE_MOUTH_HALF half its length; FACE_LINE is half a stroke's width, in
// stage units.
const float FACE_TEMPLE = 0.37, FACE_BROW = 0.454, FACE_EYE = 0.096, FACE_CHIN = -0.64;
const float FACE_MOUTH = -0.20, FACE_MOUTH_HALF = 0.20, FACE_LINE = 0.26;
// how much of a stroke is at this distance (an angle on the ball) from its line
float stroke(float d) { float w = FACE_LINE / uHead.w; return 1.0 - smoothstep(w * 0.75, w * 1.15, d); }
// an arc from temple to temple, its plane tipped up toward the front by tip
float arc(vec3 q, float tip) {
  float c = cos(tip), s = sin(tip);
  float d = abs(asin(clamp(q.y * c - q.x * s, -1.0, 1.0)) - asin(FACE_TEMPLE * c));
  // only the half of the circle that is in front of the temples
  return stroke(d) * smoothstep(-0.04, 0.02, q.x * c + (q.y - FACE_TEMPLE) * s);
}
float face(vec3 p) {
  vec3 q = (p - uHead.xyz) / uHead.w;
  float r = length(q);
  // the ball's own surface, not the neck under it or a hand held before it
  if (r > 1.05 || r < 0.93) return 0.0;
  // q as (toward the face, toward the crown, toward an ear), on the ball
  q = vec3(dot(q, uHeadF), dot(q, uHeadU), dot(q, cross(uHeadF, uHeadU))) / r;
  // the middle line, from a little behind the crown down the front
  float middle = stroke(abs(asin(clamp(q.z, -1.0, 1.0))))
    * smoothstep(FACE_CHIN - 0.03, FACE_CHIN + 0.01, q.y) * max(smoothstep(-0.02, 0.02, q.x), smoothstep(0.80, 0.84, q.y));
  float mouth = stroke(abs(asin(clamp(q.y, -1.0, 1.0)) - asin(FACE_MOUTH)))
    * (1.0 - smoothstep(FACE_MOUTH_HALF - 0.02, FACE_MOUTH_HALF + 0.02, abs(q.z))) * step(0.0, q.x);
  return max(max(middle, mouth), max(arc(q, FACE_BROW), arc(q, FACE_EYE)));
}

// The drawn line. OUTLINE is how far outside the figure the ink reaches, in
// stage units (a standing figure is 80 tall); INNER how far a surface has to
// turn from the eye before it is line, which is what parts a forearm from
// the chest it crosses; INK how dark the line is against the ground. They
// were 0.52, 0.30 and 0.42: a thin line that a phone's screen lost.
const float OUTLINE = 0.80, INNER = 0.44, INK = 0.10;
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
  float line = hit ? 0.0 : 1.0 - smoothstep(OUTLINE - 0.07, OUTLINE, closest);

  vec3 col;
  vec3 ink = uBg * INK;
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
    float tone = 0.58 + 0.24 * smoothstep(0.05, 0.14, lit) + 0.18 * smoothstep(0.50, 0.60, lit);
    float fil = 0.5 + 0.5 * dot(n, fill);
    col = base * tone * mix(0.80, 1.0, occ);
    col += base * vec3(0.30, 0.42, 0.58) * 0.10 * fil * (1.0 - smoothstep(0.03, 0.10, lit));
    col += warm * glow * 0.10;
    // The line inside the figure: where a surface turns away from the eye.
    float turn = clamp(dot(n, -rd), 0.0, 1.0);
    // Only the body takes the heavy inner line. A mat or a bench top lies
    // nearly edge-on to the eye all over, and went black with it.
    float inner = mat < 3.5 ? INNER : 0.30;
    if (mat < 0.5) col = mix(col, ink, face(p));
    col = mix(ink, col, smoothstep(inner - 0.22, inner, turn));
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
    gl.uniform1f(U("uK"), FIELD.BLEND)
    gl.uniform4fv(U("uBound"), bound)
    gl.uniform4fv(U("uHead"), [...shapes.head.at, shapes.head.r])
    gl.uniform3fv(U("uHeadF"), shapes.head.face); gl.uniform3fv(U("uHeadU"), shapes.head.crown)

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

    // A frame is drawn a band at a time, each band finished before the next.
    // Drawn in one piece it is one job for the graphics card that cannot be
    // interrupted, and this machine's driver (i915) resets any job that has
    // not made way within 640 ms of something else asking for the card: the
    // desktop redrawing, another render, its own heartbeat every 2.5 s. The
    // page's context is then lost and every frame after it is black, with no
    // error anywhere but the kernel's log ("Resetting rcs0 for preemption
    // time out"). That was every black still and blank film this camera ever
    // made, and why two renders at once never worked. A band is a few tens
    // of milliseconds.
    gl.enable(gl.SCISSOR_TEST)
    for (let i = 0; i < BANDS; i++) {
      const from = Math.floor((i * canvas.height) / BANDS), to = Math.floor(((i + 1) * canvas.height) / BANDS)
      gl.scissor(0, from, canvas.width, to - from)
      gl.drawArrays(gl.TRIANGLES, 0, 3)
      gl.finish()
    }
    gl.disable(gl.SCISSOR_TEST)
    if (gl.isContextLost()) throw new Error("the graphics card dropped the page while it drew (see the kernel's log for i915)")
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

// `muscles` is the page's list, or the three tiers of Web.Fitness.Chain:
// {primary, chain, brace}. Each is lit at its own strength.
export function prepare(track, muscles) {
  const tiers = Array.isArray(muscles) ? { primary: muscles } : muscles || {}
  const hot = new Map()
  for (const m of tiers.brace || []) hot.set(m, 0.25)
  for (const m of tiers.chain || []) hot.set(m, 0.5)
  for (const m of tiers.primary || []) hot.set(m, 1)
  const frames = track.frames.map((f, i) => {
    const J = lift(track, f)
    const things = gear(track, i, J)
    return { J, shapes: body(J, hot, { hand_a: touching(J.hand_a, things, track), hand_b: touching(J.hand_b, things, track), open: mode(track) === "plan" }), things, bound: bound(J, things) }
  })
  return { frames, cam: camera(track, frames) }
}
