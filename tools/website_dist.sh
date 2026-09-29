#!/bin/bash
# Packages meditate808.com for Cloudflare Pages: a zip of only the files the
# pages actually use, with the internal ones (README, DESIGN, the Apps Script
# sources, unused screenshots) left out. Cloudflare Pages is DIRECT UPLOAD,
# not connected to git, so this zip is what goes live.
#
#   tools/website_dist.sh [out.zip]     (default: /tmp/meditate808-site.zip)
#
# Rebuilds the legal pages from the app's markdown first, so the site can never
# ship an older policy than the app.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-/tmp/meditate808-site.zip}"
STAGE="$(mktemp -d)/site"
mkdir -p "$STAGE"

python3 tools/legal_pages.py

cd website
PAGES=(index.html privacy.html terms.html survey.html)
cp "${PAGES[@]}" _headers _redirects "$STAGE/"

# Every img/ and fonts/ path any page references, and nothing else.
grep -ohE '(img|fonts)/[A-Za-z0-9_./-]+\.(png|jpg|jpeg|svg|webp|woff2)' "${PAGES[@]}" | sort -u |
while read -r f; do
  if [ ! -f "$f" ]; then echo "MISSING: $f is referenced but not in website/" >&2; exit 1; fi
  mkdir -p "$STAGE/$(dirname "$f")"
  cp "$f" "$STAGE/$f"
done

# Copy is checked before it ships: no em dashes in anything a visitor reads.
if grep -l '—' "$STAGE"/*.html >/dev/null 2>&1; then
  echo "EM DASH in: $(grep -l '—' "$STAGE"/*.html)" >&2; exit 1
fi

rm -f "$OUT"
(cd "$STAGE" && zip -qr -X "$OUT" .)
echo "$OUT  $(du -h "$OUT" | cut -f1)  $(cd "$STAGE" && find . -type f | wc -l | tr -d ' ') files"
