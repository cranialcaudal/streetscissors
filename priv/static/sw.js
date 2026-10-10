// streetscissors service worker
const CACHE_NAME = "streetscissors-v2";

const PRECACHE_ASSETS = [
  "/images/icon-192.png",
  "/images/icon-512.png",
  "/images/preview_logo.png",
  "/favicon.ico"
];

// Install: precache app shell
self.addEventListener("install", (event) => {
  event.waitUntil(
    caches
      .open(CACHE_NAME)
      .then((cache) => cache.addAll(PRECACHE_ASSETS))
      .then(() => self.skipWaiting())
      .catch((err) => console.warn("[SW] Precache failed:", err))
  );
});

// Activate: clean up older cache versions
self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) =>
        Promise.all(
          keys
            .filter((key) => key !== CACHE_NAME)
            .map((key) => caches.delete(key))
        )
      )
      .then(() => self.clients.claim())
  );
});

// Fetch: optimized caching strategy
self.addEventListener("fetch", (event) => {
  const req = event.request;
  const url = new URL(req.url);

  // Skip non-GET, WebSockets, admin paths, and external origins
  if (
    req.method !== "GET" ||
    url.origin !== self.location.origin ||
    url.pathname.startsWith("/live") ||
    url.pathname.startsWith("/admin")
  ) {
    return;
  }

  // 1. Navigation requests (HTML pages): Network-first with cache fallback
  if (req.mode === "navigate") {
    event.respondWith(
      fetch(req)
        .then((res) => {
          if (res.ok) {
            const clone = res.clone();
            caches.open(CACHE_NAME).then((cache) => cache.put(req, clone));
          }
          return res;
        })
        .catch(async () => {
          const cached = await caches.match(req);
          if (cached) return cached;
          const fallback = await caches.match("/");
          return fallback || new Response("Offline", { status: 503, headers: { "Content-Type": "text/plain" } });
        })
    );
    return;
  }

  // 2. Static assets (CSS, JS, Fonts, Images): Cache-first with network revalidation
  const isStaticAsset =
    url.pathname.startsWith("/assets/") ||
    url.pathname.startsWith("/images/") ||
    url.pathname.startsWith("/fonts/") ||
    /\.(css|js|woff2|woff|ttf|png|jpg|jpeg|svg|webp|ico)$/i.test(url.pathname);

  if (isStaticAsset) {
    event.respondWith(
      caches.match(req).then((cached) => {
        if (cached) {
          // Revalidate in background
          fetch(req)
            .then((res) => {
              if (res.ok) {
                caches.open(CACHE_NAME).then((cache) => cache.put(req, res));
              }
            })
            .catch(() => {});
          return cached;
        }

        return fetch(req).then((res) => {
          if (res.ok) {
            const clone = res.clone();
            caches.open(CACHE_NAME).then((cache) => cache.put(req, clone));
          }
          return res;
        });
      })
    );
  }
});
