#!/bin/bash
# Pulls every camera capture off the phone and runs the lab on each pair.
#
#   ./tools/camera_pull.sh [device-udid]
#
# Files land in ~/Desktop/captures/camera/<sessionID>.csv (+ _wrist.json),
# never in the repo (public). For each pair: the probe tracks the camera's
# breathing rate, and camera_compare.py scores it against the wrist's own
# per-window results. DEBUG builds only; the Release app writes nothing.
set -euo pipefail
cd "$(dirname "$0")/.."
DEV="${1:-045D4391-3289-5F58-B71D-DE2C314BF6F6}"
OUT="$HOME/Desktop/captures/camera"
TMP="$(mktemp -d)"
mkdir -p "$OUT"
xcrun devicectl device copy from --device "$DEV" --domain-type appDataContainer \
  --domain-identifier com.lockout.meditate808 --source Documents/CameraCaptures \
  --destination "$TMP" >/dev/null
cp -n "$TMP"/CameraCaptures/* "$OUT"/ 2>/dev/null || cp -n "$TMP"/* "$OUT"/ 2>/dev/null || true
PROBE=/tmp/camera_probe
[ -x "$PROBE" ] || swiftc -O -o "$PROBE" tools/camera_probe.swift
for csv in "$OUT"/*.csv; do
  id="$(basename "$csv" .csv)"
  case "$id" in *_wrist|*_tracked) continue;; esac
  echo "===== $id ====="
  "$PROBE" "$csv" --dump-tracked "$OUT/${id}_tracked.csv" 2>/dev/null | grep -E "^== \[all six\]|^== \[whole frame\] Stillness" || true
  if [ -f "$OUT/${id}_wrist.json" ]; then
    python3 tools/camera_compare.py "$OUT/${id}_wrist.json" "$OUT/${id}_tracked.csv" auto --minutes
  else
    echo "  (no wrist result beside it: the session was discarded or never landed)"
  fi
done
