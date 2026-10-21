#!/bin/bash
#
# Re-vendors CodeMirror 6 for the admin editor:
#
#   tools/vendor/codemirror/build.sh
#
# writes assets/vendor/codemirror.js (one minified ES module) and
# assets/vendor/codemirror.LICENSE.txt. Both are committed: the site's own
# build (esbuild through mix) has no node_modules and never fetches anything,
# so only this script needs Node and the network, and only when the versions
# in package.json change. The lockfile pins every transitive package, so the
# same checkout writes the same file (CI-style check: run it, then
# `git diff --exit-code assets/vendor`).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
OUT="$ROOT/assets/vendor/codemirror.js"

cd "$HERE"
if [ -f package-lock.json ]; then npm ci --no-audit --no-fund; else npm install --no-audit --no-fund; fi

./node_modules/.bin/esbuild entry.js --bundle --format=esm --minify --target=es2022 \
  --legal-comments=none --outfile="$OUT"

# Every package bundled, with its licence, for the file's readers.
node -e '
const fs = require("fs"), path = require("path")
const seen = new Set(), out = []
function walk(dir) {
  for (const name of fs.readdirSync(dir)) {
    if (name.startsWith(".")) continue
    const p = path.join(dir, name)
    if (name.startsWith("@")) { walk(p); continue }
    const pkg = path.join(p, "package.json")
    if (!fs.existsSync(pkg)) continue
    const j = JSON.parse(fs.readFileSync(pkg, "utf8"))
    if (j.name === "esbuild" || j.name.startsWith("@esbuild/") || seen.has(j.name)) continue
    seen.add(j.name)
    const lic = fs.readdirSync(p).find(f => /^licen[sc]e/i.test(f))
    out.push(`${j.name} ${j.version} (${j.license})\n\n` + (lic ? fs.readFileSync(path.join(p, lic), "utf8").trim() : "") + "\n")
  }
}
walk("node_modules")
out.sort()
fs.writeFileSync(process.argv[1], "Bundled into codemirror.js by tools/vendor/codemirror/build.sh.\n\n" + out.join("\n" + "-".repeat(72) + "\n\n"))
' "$ROOT/assets/vendor/codemirror.LICENSE.txt"

echo "wrote $OUT ($(wc -c < "$OUT") bytes)"
