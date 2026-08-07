// Biometric chart hook — line, violin, waterfall rendered on a single canvas.

const PAD = { top: 28, right: 20, bottom: 42, left: 48 }
const COLORS = {
  score: "#a78bfa",
  hrv_ms: "#34d399",
  sleep_hours: "#60a5fa",
  weight_lbs: "#fb923c",
  resting_hr: "#f472b6",
  active_calories: "#facc15",
  protein_grams: "#a3e635",
  water_oz: "#22d3ee",
  energy: "#c084fc",
  soreness: "#f87171",
  default: "#6b7280",
}
const GRID = "rgba(255,255,255,0.05)"
const TEXT = "#555"
const LINE_W = 1.5

function color(metric) { return COLORS[metric] || COLORS.default }

// ── Shared helpers ────────────────────────────────────────────────────────────

function setupCanvas(canvas) {
  const dpr = window.devicePixelRatio || 1
  const w = canvas.clientWidth
  const h = canvas.clientHeight
  canvas.width = w * dpr
  canvas.height = h * dpr
  const ctx = canvas.getContext("2d")
  ctx.scale(dpr, dpr)
  ctx.clearRect(0, 0, w, h)
  return { ctx, w, h }
}

function innerRect(w, h) {
  return {
    x0: PAD.left, y0: PAD.top,
    x1: w - PAD.right, y1: h - PAD.bottom,
    iw: w - PAD.left - PAD.right,
    ih: h - PAD.top - PAD.bottom,
  }
}

function niceRange(values) {
  const min = Math.min(...values)
  const max = Math.max(...values)
  const span = max - min || 1
  return { lo: min - span * 0.08, hi: max + span * 0.08 }
}

function drawGrid(ctx, r, yTicks) {
  ctx.strokeStyle = GRID
  ctx.lineWidth = 1
  yTicks.forEach(({ y }) => {
    ctx.beginPath()
    ctx.moveTo(r.x0, y)
    ctx.lineTo(r.x1, y)
    ctx.stroke()
  })
}

function label(ctx, text, x, y, align = "center", size = 10) {
  ctx.font = `${size}px monospace`
  ctx.fillStyle = TEXT
  ctx.textAlign = align
  ctx.fillText(text, x, y)
}

// ── Line chart ────────────────────────────────────────────────────────────────

export function renderLine(canvas, entries, metric, hoverFrac) {
  const points = entries
    .map(e => ({ date: e.date, v: e[metric] }))
    .filter(p => p.v != null)

  if (points.length < 2) {
    const { ctx, w, h } = setupCanvas(canvas)
    label(ctx, "not enough data yet", w / 2, h / 2, "center", 12)
    return
  }

  const { ctx, w, h } = setupCanvas(canvas)
  const r = innerRect(w, h)
  const vals = points.map(p => p.v)
  const { lo, hi } = niceRange(vals)
  const span = hi - lo

  const xOf = i => r.x0 + (i / (points.length - 1)) * r.iw
  const yOf = v => r.y1 - ((v - lo) / span) * r.ih

  // y-axis ticks
  const ySteps = 5
  const yTicks = Array.from({ length: ySteps + 1 }, (_, i) => {
    const v = lo + (span * i) / ySteps
    return { v, y: yOf(v) }
  })
  drawGrid(ctx, r, yTicks)
  yTicks.forEach(({ v, y }) => label(ctx, Math.round(v), r.x0 - 6, y + 4, "right"))

  // x-axis date labels (up to 6)
  const step = Math.max(1, Math.floor(points.length / 6))
  points.forEach((p, i) => {
    if (i % step === 0 || i === points.length - 1) {
      label(ctx, p.date.slice(5), xOf(i), r.y1 + 16, "center")
    }
  })

  // filled area
  const c = color(metric)
  ctx.beginPath()
  ctx.moveTo(xOf(0), r.y1)
  points.forEach((p, i) => ctx.lineTo(xOf(i), yOf(p.v)))
  ctx.lineTo(xOf(points.length - 1), r.y1)
  ctx.closePath()
  ctx.fillStyle = c + "22"
  ctx.fill()

  // line
  ctx.beginPath()
  points.forEach((p, i) => {
    if (i === 0) ctx.moveTo(xOf(i), yOf(p.v))
    else ctx.lineTo(xOf(i), yOf(p.v))
  })
  ctx.strokeStyle = c
  ctx.lineWidth = LINE_W
  ctx.lineJoin = "round"
  ctx.stroke()

  // dots
  points.forEach((p, i) => {
    ctx.beginPath()
    ctx.arc(xOf(i), yOf(p.v), 3, 0, Math.PI * 2)
    ctx.fillStyle = c
    ctx.fill()
  })

  // hover crosshair + tooltip
  if (hoverFrac != null) {
    const idx = Math.round(hoverFrac * (points.length - 1))
    const p = points[Math.max(0, Math.min(idx, points.length - 1))]
    const hx = xOf(points.indexOf(p) >= 0 ? points.indexOf(p) : idx)
    const hy = yOf(p.v)

    ctx.strokeStyle = "rgba(255,255,255,0.2)"
    ctx.lineWidth = 1
    ctx.setLineDash([4, 4])
    ctx.beginPath(); ctx.moveTo(hx, r.y0); ctx.lineTo(hx, r.y1); ctx.stroke()
    ctx.setLineDash([])

    ctx.beginPath()
    ctx.arc(hx, hy, 5, 0, Math.PI * 2)
    ctx.fillStyle = c
    ctx.fill()
    ctx.strokeStyle = "#fff"
    ctx.lineWidth = 1.5
    ctx.stroke()

    const tip = `${p.date.slice(5)}  ${Math.round(p.v * 10) / 10}`
    const tw = ctx.measureText(tip).width + 16
    const tx = Math.min(Math.max(hx - tw / 2, r.x0), r.x1 - tw)
    const ty = hy - 28
    ctx.fillStyle = "rgba(0,0,0,0.75)"
    ctx.beginPath()
    ctx.roundRect(tx, ty, tw, 20, 4)
    ctx.fill()
    ctx.fillStyle = "#eee"
    ctx.font = "11px monospace"
    ctx.textAlign = "left"
    ctx.fillText(tip, tx + 8, ty + 14)
  }

  // metric label top-left
  label(ctx, metric.replace(/_/g, " "), r.x0, r.y0 - 8, "left", 10)
}

// ── Violin chart ──────────────────────────────────────────────────────────────

const VIOLIN_METRICS = [
  { key: "score", label: "Score" },
  { key: "hrv_ms", label: "HRV" },
  { key: "sleep_hours", label: "Sleep" },
  { key: "resting_hr", label: "RHR" },
  { key: "energy", label: "Energy" },
  { key: "soreness", label: "Soreness" },
]

function kde(values, bandwidth, nPoints = 60) {
  if (values.length === 0) return []
  const lo = Math.min(...values)
  const hi = Math.max(...values)
  const step = (hi - lo) / (nPoints - 1) || 1
  return Array.from({ length: nPoints }, (_, i) => {
    const x = lo + i * step
    const density = values.reduce((sum, v) => {
      const u = (x - v) / bandwidth
      return sum + Math.exp(-0.5 * u * u)
    }, 0) / (values.length * bandwidth * Math.sqrt(2 * Math.PI))
    return { x, density }
  })
}

function scotts(values) {
  const n = values.length
  if (n < 2) return 1
  const mean = values.reduce((a, b) => a + b, 0) / n
  const variance = values.reduce((s, v) => s + (v - mean) ** 2, 0) / (n - 1)
  return 1.06 * Math.sqrt(variance) * Math.pow(n, -0.2) || 1
}

export function renderViolin(canvas, entries) {
  const metrics = VIOLIN_METRICS.filter(m => entries.some(e => e[m.key] != null))

  if (metrics.length === 0) {
    const { ctx, w, h } = setupCanvas(canvas)
    label(ctx, "not enough data yet", w / 2, h / 2, "center", 12)
    return
  }

  const { ctx, w, h } = setupCanvas(canvas)
  const r = innerRect(w, h)
  const slotW = r.iw / metrics.length

  metrics.forEach(({ key, label: lbl }, mi) => {
    const vals = entries.map(e => e[key]).filter(v => v != null)
    if (vals.length < 3) return

    const lo = Math.min(...vals)
    const hi = Math.max(...vals)
    const span = hi - lo || 1

    const bw = scotts(vals)
    const curve = kde(vals, bw)
    const maxDensity = Math.max(...curve.map(p => p.density)) || 1
    const halfW = slotW * 0.38

    const cx = r.x0 + mi * slotW + slotW / 2
    const yOf = v => r.y1 - ((v - lo) / span) * r.ih

    // violin shape
    const c = color(key)
    ctx.beginPath()
    curve.forEach((p, i) => {
      const xr = cx + (p.density / maxDensity) * halfW
      if (i === 0) ctx.moveTo(xr, yOf(p.x))
      else ctx.lineTo(xr, yOf(p.x))
    })
    ;[...curve].reverse().forEach(p => {
      ctx.lineTo(cx - (p.density / maxDensity) * halfW, yOf(p.x))
    })
    ctx.closePath()
    ctx.fillStyle = c + "33"
    ctx.fill()
    ctx.strokeStyle = c
    ctx.lineWidth = 1.5
    ctx.stroke()

    // median line
    const sorted = [...vals].sort((a, b) => a - b)
    const median = sorted[Math.floor(sorted.length / 2)]
    ctx.strokeStyle = c
    ctx.lineWidth = 2
    ctx.beginPath()
    ctx.moveTo(cx - halfW * 0.5, yOf(median))
    ctx.lineTo(cx + halfW * 0.5, yOf(median))
    ctx.stroke()

    // latest value dot
    const latest = entries[entries.length - 1]?.[key]
    if (latest != null) {
      ctx.beginPath()
      ctx.arc(cx, yOf(latest), 4, 0, Math.PI * 2)
      ctx.fillStyle = "#fff"
      ctx.fill()
      ctx.strokeStyle = c
      ctx.lineWidth = 1.5
      ctx.stroke()
    }

    // y ticks (min/max)
    label(ctx, Math.round(hi * 10) / 10, cx, r.y0 - 4, "center", 9)
    label(ctx, Math.round(lo * 10) / 10, cx, r.y1 + 12, "center", 9)

    // metric label
    label(ctx, lbl, cx, h - 10, "center", 10)
  })

  // legend: white dot = latest
  ctx.beginPath()
  ctx.arc(r.x0 + 6, r.y0 - 8, 3, 0, Math.PI * 2)
  ctx.fillStyle = "#fff"
  ctx.fill()
  label(ctx, "latest", r.x0 + 14, r.y0 - 4, "left", 9)
}

// ── Waterfall chart ───────────────────────────────────────────────────────────

const WATERFALL_METRICS = [
  { key: "sleep_hours", label: "Sleep", goal: 8, dir: "higher" },
  { key: "hrv_ms", label: "HRV", goal: 60, dir: "higher" },
  { key: "energy", label: "Energy", goal: 7, dir: "higher" },
  { key: "soreness", label: "Soreness", goal: 3, dir: "lower" },
  { key: "protein_grams", label: "Protein", goal: 160, dir: "higher" },
  { key: "resting_hr", label: "RHR", goal: 55, dir: "lower" },
  { key: "water_oz", label: "Water", goal: 100, dir: "higher" },
  { key: "active_calories", label: "Active cal", goal: 600, dir: "higher" },
]

const WEIGHTS = {
  sleep_hours: 3, hrv_ms: 3, energy: 2, soreness: 2,
  protein_grams: 1.5, resting_hr: 1.5, water_oz: 1, active_calories: 1,
}

function pct(v, goal, dir) {
  if (dir === "higher") return Math.min(v / goal * 100, 100)
  return Math.max(Math.min((2 * goal - v) / goal * 100, 100), 0)
}

export function renderWaterfall(canvas, entries) {
  const latest = entries[entries.length - 1]
  if (!latest) {
    const { ctx, w, h } = setupCanvas(canvas)
    label(ctx, "no data yet", w / 2, h / 2, "center", 12)
    return
  }

  const { ctx, w, h } = setupCanvas(canvas)
  const r = innerRect(w, h)

  const present = WATERFALL_METRICS.filter(m => latest[m.key] != null)
  if (present.length === 0) {
    label(ctx, "no scored fields in latest entry", w / 2, h / 2, "center", 12)
    return
  }

  // compute per-metric contribution to the 100-point score
  const totalW = present.reduce((s, m) => s + WEIGHTS[m.key], 0)
  const bars = present.map(m => {
    const score = pct(latest[m.key], m.goal, m.dir)
    const w = WEIGHTS[m.key]
    const contribution = score * w / totalW
    const fullSlot = 100 * w / totalW
    const penalty = fullSlot - contribution
    return { ...m, score, contribution, fullSlot, penalty }
  })

  const totalScore = Math.round(bars.reduce((s, b) => s + b.contribution, 0))

  // columns: [Start 100] + [bars] + [Total]
  const cols = [{ id: "start", label: "Perfect", value: 100, base: 0, isStart: true }]
  let running = 100
  bars.forEach(b => {
    const delta = -(b.penalty)
    cols.push({ id: b.key, label: b.label, value: delta, base: running, isPenalty: true, pct: b.score })
    running += delta
  })
  cols.push({ id: "total", label: "Score", value: totalScore, base: 0, isTotal: true })

  const barCount = cols.length
  const slotW = r.iw / barCount
  const barW = slotW * 0.6

  const yOf = v => r.y1 - (v / 100) * r.ih

  // y grid
  ;[0, 25, 50, 75, 100].forEach(v => {
    ctx.strokeStyle = GRID
    ctx.lineWidth = 1
    ctx.beginPath(); ctx.moveTo(r.x0, yOf(v)); ctx.lineTo(r.x1, yOf(v)); ctx.stroke()
    label(ctx, v, r.x0 - 6, yOf(v) + 4, "right")
  })

  // connector lines between bars
  let runningForLine = 100
  cols.forEach((col, i) => {
    if (col.isStart || col.isTotal) return
    const nextX = r.x0 + (i + 1) * slotW - slotW * 0.3
    const y = yOf(runningForLine + col.value)
    ctx.strokeStyle = "rgba(255,255,255,0.1)"
    ctx.lineWidth = 1
    ctx.setLineDash([3, 3])
    ctx.beginPath(); ctx.moveTo(r.x0 + i * slotW + slotW * 0.3 + barW, y); ctx.lineTo(nextX, y); ctx.stroke()
    ctx.setLineDash([])
    runningForLine += col.value
  })

  // draw bars
  cols.forEach((col, i) => {
    const cx = r.x0 + i * slotW + slotW / 2
    const bx = cx - barW / 2

    let top, bot, fillColor
    if (col.isStart) {
      top = yOf(100); bot = r.y1
      fillColor = "rgba(255,255,255,0.08)"
    } else if (col.isTotal) {
      top = yOf(col.value); bot = r.y1
      fillColor = col.value >= 80 ? "#4ade8055" : col.value >= 60 ? "#facc1555" : "#f8717155"
    } else {
      top = yOf(col.base + col.value)
      bot = yOf(col.base)
      fillColor = col.pct >= 80 ? "#4ade8033" : col.pct >= 50 ? "#facc1533" : "#f8717133"
    }

    const barH = Math.abs(bot - top)
    const barTop = Math.min(top, bot)

    ctx.fillStyle = fillColor
    ctx.beginPath()
    ctx.roundRect(bx, barTop, barW, barH, 3)
    ctx.fill()

    // stroke
    const strokeColor = col.isTotal
      ? (col.value >= 80 ? "#4ade80" : col.value >= 60 ? "#facc15" : "#f87171")
      : col.pct >= 80 ? "#4ade80" : col.pct >= 50 ? "#facc15" : "#f87171"

    if (!col.isStart) {
      ctx.strokeStyle = strokeColor
      ctx.lineWidth = 1.5
      ctx.beginPath(); ctx.roundRect(bx, barTop, barW, barH, 3); ctx.stroke()
    }

    // value label inside/above bar
    const valText = col.isStart ? "100" : col.isTotal ? totalScore : `${Math.round(col.pct)}`
    ctx.fillStyle = "#ccc"
    ctx.font = "bold 11px monospace"
    ctx.textAlign = "center"
    ctx.fillText(valText, cx, barTop - 5)

    // x label
    label(ctx, col.label, cx, h - 8, "center", 9)
  })

  // title
  label(ctx, `score breakdown — ${latest.date}`, r.x0, r.y0 - 8, "left", 10)
}

// ── Hook ──────────────────────────────────────────────────────────────────────

export const BiometricCharts = {
  mounted() {
    this.data = null
    this.chartType = this.el.dataset.chartType || "line"
    this.lineMetric = this.el.dataset.lineMetric || "score"
    this.hoverFrac = null

    this.handleEvent("biometrics:data", data => {
      this.data = data
      this.render()
    })

    this.handleEvent("biometrics:chart", ({ type, metric }) => {
      this.chartType = type
      if (metric) this.lineMetric = metric
      this.render()
    })

    this.onResize = () => this.render()
    window.addEventListener("resize", this.onResize)

    this.onMove = e => {
      const rect = this.el.getBoundingClientRect()
      this.hoverFrac = (e.clientX - rect.left - PAD.left) / (rect.width - PAD.left - PAD.right)
      this.hoverFrac = Math.max(0, Math.min(1, this.hoverFrac))
      this.render()
    }
    this.onLeave = () => { this.hoverFrac = null; this.render() }
    this.el.addEventListener("mousemove", this.onMove)
    this.el.addEventListener("mouseleave", this.onLeave)
  },

  destroyed() {
    window.removeEventListener("resize", this.onResize)
    this.el.removeEventListener("mousemove", this.onMove)
    this.el.removeEventListener("mouseleave", this.onLeave)
  },

  render() {
    if (!this.data) return
    const { entries } = this.data

    if (this.chartType === "line") {
      renderLine(this.el, entries, this.lineMetric, this.hoverFrac)
    } else if (this.chartType === "violin") {
      renderViolin(this.el, entries)
    } else if (this.chartType === "waterfall") {
      renderWaterfall(this.el, entries)
    }
  }
}
