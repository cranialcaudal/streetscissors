// The activity plate: a ride's published route on a live map, with its
// elevation profile beneath. The route arrives in `data-route` already cut by
// the privacy zones (Web.Rides.Route) — this file only draws what it is given.
//
// MapLibre is a megabyte, so it is fetched the first time a plate mounts
// rather than on every page of the site.

const STYLE = "https://tiles.openfreemap.org/styles/positron"

const miles = (m) => (m / 1609.344).toFixed(1) + " mi"
const feet = (m) => Math.round(m * 3.28084).toLocaleString("en-US") + " ft"

const lineFeature = (segments) => ({
  type: "Feature",
  properties: {},
  geometry: {
    type: "MultiLineString",
    coordinates: segments.map((segment) => segment.map(([lng, lat]) => [lng, lat])),
  },
})

const pointFeature = (lngLat, kind) => ({
  type: "Feature",
  properties: { kind },
  geometry: { type: "Point", coordinates: lngLat },
})

export const RouteMap = {
  async mounted() {
    const route = JSON.parse(this.el.dataset.route)
    this.points = route.segments.flat()
    if (this.points.length < 2) return

    const { default: maplibregl } = await import("../vendor/maplibre-gl.js")
    // The plate can be patched away while the library is still downloading.
    if (!this.el.isConnected) return

    const style = getComputedStyle(this.el)
    const color = style.getPropertyValue("--sport-color").trim() || "#ff6a2b"
    const ground = style.getPropertyValue("--paper-deep").trim() || "#ffffff"

    const bounds = new maplibregl.LngLatBounds()
    this.points.forEach(([lng, lat]) => bounds.extend([lng, lat]))

    this.map = new maplibregl.Map({
      container: this.el.querySelector("[data-role=map]"),
      style: STYLE,
      bounds,
      fitBoundsOptions: { padding: 48, maxZoom: 15 },
      maxZoom: 17,
      // A plate sits in the page's scroll path: one finger or a bare wheel
      // scrolls the page, and the map takes two fingers or ctrl.
      cooperativeGestures: true,
    })

    this.map.addControl(new maplibregl.NavigationControl({ showCompass: false }), "top-right")

    this.map.on("load", () => {
      // Only ends the route really has: an end made by a privacy zone is not
      // where the activity started or stopped, and is not marked as one.
      const ends = []
      const first = this.points[0]
      const last = this.points[this.points.length - 1]
      if (route.start) ends.push(pointFeature([first[0], first[1]], "start"))
      if (route.finish) ends.push(pointFeature([last[0], last[1]], "finish"))

      this.map.addSource("route", { type: "geojson", data: lineFeature(route.segments) })
      this.map.addSource("ends", {
        type: "geojson",
        data: { type: "FeatureCollection", features: ends },
      })
      this.map.addSource("cursor", {
        type: "geojson",
        data: { type: "FeatureCollection", features: [] },
      })

      const round = { "line-cap": "round", "line-join": "round" }

      this.map.addLayer({
        id: "route-casing",
        type: "line",
        source: "route",
        layout: round,
        paint: { "line-color": ground, "line-width": 7 },
      })
      this.map.addLayer({
        id: "route",
        type: "line",
        source: "route",
        layout: round,
        paint: { "line-color": color, "line-width": 4 },
      })
      this.map.addLayer({
        id: "ends",
        type: "circle",
        source: "ends",
        paint: {
          "circle-radius": 6,
          "circle-color": ["match", ["get", "kind"], "start", ground, color],
          "circle-stroke-color": color,
          "circle-stroke-width": 3,
        },
      })
      this.map.addLayer({
        id: "cursor",
        type: "circle",
        source: "cursor",
        paint: {
          "circle-radius": 7,
          "circle-color": color,
          "circle-stroke-color": ground,
          "circle-stroke-width": 3,
        },
      })
    })

    this.bindProfile()
  },

  // Running a pointer along the profile walks a dot along the route.
  bindProfile() {
    const figure = this.el.querySelector(".activity-profile")
    if (!figure) return

    const svg = figure.querySelector("[data-role=profile]")
    const cursor = figure.querySelector("[data-role=cursor]")
    const readout = figure.querySelector("[data-role=readout]")
    const length = Number(figure.dataset.length)
    const width = svg.viewBox.baseVal.width

    const show = (event) => {
      const box = svg.getBoundingClientRect()
      const share = Math.min(1, Math.max(0, (event.clientX - box.left) / box.width))
      const point = this.nearest(share * length)

      cursor.setAttribute("x1", share * width)
      cursor.setAttribute("x2", share * width)
      cursor.removeAttribute("hidden")
      readout.textContent =
        miles(point[2]) + (point[3] == null ? "" : " · " + feet(point[3]))

      this.setCursor([pointFeature([point[0], point[1]], "cursor")])
    }

    const hide = () => {
      cursor.setAttribute("hidden", "")
      readout.textContent = ""
      this.setCursor([])
    }

    svg.addEventListener("pointermove", show)
    svg.addEventListener("pointerdown", show)
    svg.addEventListener("pointerleave", hide)
  },

  // The point whose distance along the route is closest to `distance`.
  // Distances only ever grow, so this is a bisection.
  nearest(distance) {
    let low = 0
    let high = this.points.length - 1

    while (high - low > 1) {
      const middle = (low + high) >> 1
      if (this.points[middle][2] < distance) low = middle
      else high = middle
    }

    return distance - this.points[low][2] < this.points[high][2] - distance
      ? this.points[low]
      : this.points[high]
  },

  setCursor(features) {
    const source = this.map && this.map.getSource("cursor")
    if (source) source.setData({ type: "FeatureCollection", features })
  },

  destroyed() {
    if (this.map) this.map.remove()
  },
}
