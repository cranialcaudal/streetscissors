// Leaflet map + elevation profile hooks for /rides.
// Points arrive via push_event only ("ride:init", "ride:append",
// "elevation:init") — never embedded in the DOM.
import * as L from "../vendor/leaflet.js"

const TRAIL_STYLE = { color: "#C8102E", weight: 3, opacity: 0.9 }
const HOVER_EVENT = "ride:elevation-hover"

const osmLayer = () =>
  L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
    maxZoom: 19,
    attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
  })

const topoLayer = () =>
  L.tileLayer("https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png", {
    maxZoom: 17,
    subdomains: ["a", "b", "c"],
    attribution:
      'map data: &copy; OpenStreetMap contributors, SRTM | style: &copy; <a href="https://opentopomap.org">OpenTopoMap</a> (CC-BY-SA)',
  })

export const RideMap = {
  mounted() {
    this.mode = this.el.dataset.mode || "static"
    this.map = L.map(this.el)
    this.osm = osmLayer().addTo(this.map)
    this.topo = topoLayer()
    this.map.setView([54.54, -3.15], 9) // placeholder view until points arrive
    this.polyline = L.polyline([], TRAIL_STYLE).addTo(this.map)
    this.dot = null
    this.hoverDot = null

    this.addLayerToggle()

    this.handleEvent("ride:init", ({ points }) => {
      this.polyline.setLatLngs(points)
      if (points.length > 0) {
        this.map.fitBounds(this.polyline.getBounds(), { padding: [30, 30] })
        if (this.mode === "live") this.moveDot(points[points.length - 1])
      }
    })

    this.handleEvent("ride:append", ({ points }) => {
      points.forEach((p) => this.polyline.addLatLng(p))
      if (points.length > 0 && this.mode === "live") {
        const last = points[points.length - 1]
        this.moveDot(last)
        this.map.panTo(last)
      }
    })

    // Hover sync from the elevation profile (fraction of total distance).
    this.onHover = (e) => {
      const frac = e.detail.frac
      const latlngs = this.polyline.getLatLngs()
      if (frac == null || latlngs.length === 0) {
        if (this.hoverDot) this.hoverDot.remove()
        this.hoverDot = null
        return
      }
      const point = latlngs[Math.round(frac * (latlngs.length - 1))]
      if (!this.hoverDot) {
        this.hoverDot = L.circleMarker(point, {
          radius: 6, color: "#fff", weight: 2, fillColor: "#C8102E", fillOpacity: 1,
        }).addTo(this.map)
      } else {
        this.hoverDot.setLatLng(point)
      }
    }
    window.addEventListener(HOVER_EVENT, this.onHover)
  },

  destroyed() {
    window.removeEventListener(HOVER_EVENT, this.onHover)
    this.map.remove()
  },

  moveDot(latlng) {
    if (!this.dot) {
      this.dot = L.circleMarker(latlng, {
        radius: 7, color: "#fff", weight: 2, fillColor: "#f43f5e", fillOpacity: 1,
      }).addTo(this.map)
    } else {
      this.dot.setLatLng(latlng)
    }
  },

  // Custom street/topo button instead of L.control.layers: the stock control
  // needs leaflet's bundled icon images, which we don't ship.
  addLayerToggle() {
    const control = new L.Control({ position: "topright" })
    control.onAdd = () => {
      const btn = L.DomUtil.create("button", "ride-map-toggle")
      btn.type = "button"
      btn.textContent = "topo"
      L.DomEvent.disableClickPropagation(btn)
      L.DomEvent.on(btn, "click", () => {
        const topoOn = this.map.hasLayer(this.topo)
        if (topoOn) {
          this.map.removeLayer(this.topo)
          this.osm.addTo(this.map)
        } else {
          this.map.removeLayer(this.osm)
          this.topo.addTo(this.map)
        }
        btn.textContent = topoOn ? "topo" : "street"
      })
      return btn
    }
    control.addTo(this.map)
  },
}

export const ElevationProfile = {
  mounted() {
    this.dist = []
    this.ele = []
    this.hoverX = null

    this.handleEvent("elevation:init", ({ dist, ele }) => {
      this.dist = dist
      this.ele = ele
      this.el.style.display = ele.length > 1 ? "" : "none"
      this.draw()
    })

    this.onMove = (e) => {
      const rect = this.el.getBoundingClientRect()
      this.hoverX = Math.min(Math.max(e.clientX - rect.left, 0), rect.width)
      this.draw()
      const frac = rect.width > 0 ? this.hoverX / rect.width : 0
      window.dispatchEvent(new CustomEvent(HOVER_EVENT, { detail: { frac } }))
    }
    this.onLeave = () => {
      this.hoverX = null
      this.draw()
      window.dispatchEvent(new CustomEvent(HOVER_EVENT, { detail: { frac: null } }))
    }
    this.onResize = () => this.draw()

    this.el.addEventListener("mousemove", this.onMove)
    this.el.addEventListener("mouseleave", this.onLeave)
    window.addEventListener("resize", this.onResize)
  },

  destroyed() {
    this.el.removeEventListener("mousemove", this.onMove)
    this.el.removeEventListener("mouseleave", this.onLeave)
    window.removeEventListener("resize", this.onResize)
  },

  draw() {
    if (this.ele.length < 2) return
    const canvas = this.el
    const dpr = window.devicePixelRatio || 1
    const width = canvas.clientWidth
    const height = canvas.clientHeight
    canvas.width = width * dpr
    canvas.height = height * dpr

    const ctx = canvas.getContext("2d")
    ctx.scale(dpr, dpr)
    ctx.clearRect(0, 0, width, height)

    const minEle = Math.min(...this.ele)
    const maxEle = Math.max(...this.ele)
    const span = Math.max(maxEle - minEle, 10)
    const totalDist = this.dist[this.dist.length - 1] || 1
    const pad = 6

    const x = (d) => (d / totalDist) * width
    const y = (e) => height - pad - ((e - minEle) / span) * (height - 2 * pad)

    // filled area under the profile
    ctx.beginPath()
    ctx.moveTo(x(this.dist[0]), height)
    this.dist.forEach((d, i) => ctx.lineTo(x(d), y(this.ele[i])))
    ctx.lineTo(width, height)
    ctx.closePath()
    ctx.fillStyle = "rgba(42, 82, 190, 0.25)"
    ctx.fill()

    // profile line
    ctx.beginPath()
    this.dist.forEach((d, i) => {
      if (i === 0) ctx.moveTo(x(d), y(this.ele[i]))
      else ctx.lineTo(x(d), y(this.ele[i]))
    })
    ctx.strokeStyle = "#8fa9e8"
    ctx.lineWidth = 1.5
    ctx.stroke()

    if (this.hoverX != null) {
      // nearest sample to the cursor
      const targetDist = (this.hoverX / width) * totalDist
      let i = this.dist.findIndex((d) => d >= targetDist)
      if (i < 0) i = this.dist.length - 1

      ctx.beginPath()
      ctx.moveTo(this.hoverX, 0)
      ctx.lineTo(this.hoverX, height)
      ctx.strokeStyle = "rgba(255,255,255,0.4)"
      ctx.lineWidth = 1
      ctx.stroke()

      const miles = (this.dist[i] / 1609.344).toFixed(1)
      const feet = Math.round(this.ele[i] * 3.28084)
      const label = `${miles} mi · ${feet} ft`
      ctx.font = "11px monospace"
      const textW = ctx.measureText(label).width
      const tx = Math.min(this.hoverX + 8, width - textW - 4)
      ctx.fillStyle = "#fff"
      ctx.fillText(label, tx, 14)
    }
  },
}
