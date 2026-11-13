#!/bin/bash
# Takes the white paper out of every companion image and re-installs them
# everywhere they are used (2026-11-13, Melvin: "white in the enclosed corners
# of the dragon's tail curl, and a lot of white in the corners and between the
# feathers of the phoenix").
#
#   tools/companion_clean.sh <cleanMasterDir> [<rigMasterDir>]     # from the repo root
#
# <cleanMasterDir> holds the cleaned 2x masters <form>-<n>.png (1328 x 1488),
# made by `paper_check fix` with the keep boxes below, run twice (the second
# pass takes the last few fringe pixels the first one exposed); `--fix
# <srcDir>` runs that step too, writing into <cleanMasterDir>.
# <rigMasterDir> is the master set the Rive rigs were cut from, kept on
# Melvin's Mac as mockups/companions/master-before-clean/ (untracked, like
# master/): every rig image is re-cut from the clean art on EXACTLY those
# boxes (companion_cut BOXES_FROM). Cleaning drops specks round the edge, so
# the clean art's own boxes are a few px smaller; cutting on them would move
# every body and chest the hats and rig numbers were measured against.
#
# Writes:
#   mockups/companions/<form>-<n>.png      664 x 744 previews (sips -Z 744 of the master)
#   app, widget and Watch stills           tools/companion_stills.sh
#   Coherence/Otto/Companion<Form>.riv     bodies and chest patches swapped in place
#                                          (tools/riv_images.py, no editor needed)
set -euo pipefail
cd "$(dirname "$0")/.."
FIX_SRC=""
if [ "${1:-}" = "--fix" ]; then FIX_SRC=$2; shift 2; fi
CLEAN=$1
RIGSRC=${2:-mockups/companions/master-before-clean}
TMP=$(mktemp -d)
swiftc -O tools/paper_check.swift -o "$TMP/paper_check"
swiftc -O tools/companion_cut.swift -o "$TMP/companion_cut"

# The keep boxes, in 2x master pixels: the stage-1 cobwebs. Their strands and
# edges stay as drawn; the paper the web was drawn across still goes.
keeps() {
  case "$1-$2" in
    redpanda-1) echo "--keep-strands 940,560,140,340:stage-1-cobweb --keep-strands 280,620,110,260:stage-1-cobweb" ;;
    tiger-1)    echo "--keep-strands 340,620,230,360:stage-1-cobweb --keep-strands 940,640,110,180:stage-1-cobweb" ;;
    phoenix-1)  echo "--keep-strands 400,600,200,380:stage-1-cobweb --keep-strands 780,740,120,220:stage-1-cobweb" ;;
    dragon-1)   echo "--keep-strands 340,340,260,760:stage-1-cobweb" ;;
    *) echo "" ;;
  esac
}
# The same boxes for an image at <scale> x the master, shifted by <dx>,<dy>
# (a rig body is a crop): keeps_at form stage scale [dx dy]
keeps_at() {
  keeps "$1" "$2" | python3 -c '
import sys
k, dx, dy = float(sys.argv[1]), float(sys.argv[2]), float(sys.argv[3])
t = sys.stdin.read().split(); out = []
for i in range(0, len(t), 2):
    box, why = t[i + 1].split(":", 1)
    x, y, w, h = [float(v) for v in box.split(",")]
    out.append("%s %d,%d,%d,%d:%s" % (t[i], x * k - dx, y * k - dy, w * k + 2, h * k + 2, why))
print(" ".join(out))' "$3" "${4:-0}" "${5:-0}"
}
# A resampled copy can still show a one-pixel white speck at a feather or fur
# tip where the master had a few faint ones; one pass at its own scale takes
# them (the rule's distances scale with --scale). polish file scale [dx dy]
polish() {
  local file=$1 scale=$2 f n
  f=$(basename "$file" .png); n=${f##*[!0-9]}; f=$(echo "$f" | tr 'A-Z' 'a-z' | sed 's/^companion//;s/^widget//;s/^watch//;s/-body-[0-9]*$//;s/-[0-9]*$//;s/[0-9]*$//')
  # shellcheck disable=SC2046
  local k; k=$(keeps_at "$f" "$n" "$scale" "${3:-0}" "${4:-0}")
  # two passes, as for the masters
  # shellcheck disable=SC2086
  "$TMP/paper_check" fix "$file" "$file" --scale "$scale" $k >/dev/null
  # shellcheck disable=SC2086
  "$TMP/paper_check" fix "$file" "$file" --scale "$scale" $k >/dev/null
}

if [ -n "$FIX_SRC" ]; then
  mkdir -p "$CLEAN"
  for f in redpanda tiger phoenix dragon; do
    for n in 1 2 3 4 5 6 7; do
      # shellcheck disable=SC2046
      ( "$TMP/paper_check" fix "$FIX_SRC/$f-$n.png" "$TMP/pass1-$f-$n.png" $(keeps $f $n) >/dev/null
        "$TMP/paper_check" fix "$TMP/pass1-$f-$n.png" "$CLEAN/$f-$n.png" $(keeps $f $n) | tail -1 ) &
    done
    wait
  done
fi

for f in redpanda tiger phoenix dragon; do
  for n in 1 2 3 4 5 6 7; do
    sips -Z 744 "$CLEAN/$f-$n.png" --out "mockups/companions/$f-$n.png" >/dev/null
    polish "mockups/companions/$f-$n.png" 0.5 &
  done
  wait
done
tools/companion_stills.sh
for key in RedPanda Tiger Phoenix Dragon; do
  for n in 1 2 3 4 5 6 7; do
    polish "OttoWidget/Assets.xcassets/Widget$key$n.imageset/Widget$key$n.png" 0.302 &
    polish "CoherenceWatch/Assets.xcassets/Watch$key$n.imageset/Watch$key$n.png" 0.242 &
  done
  wait
done

export RIVE_GENERATED=${RIVE_GENERATED:-$(ls -d ~/Library/Developer/Xcode/DerivedData/*/SourcePackages/checkouts/rive-ios/submodules/rive-runtime/include/rive/generated 2>/dev/null | head -1)}
for pair in redpanda:RedPanda tiger:Tiger phoenix:Phoenix dragon:Dragon; do
  f=${pair%%:*}; key=${pair##*:}
  chest=""; [ "$f" = redpanda ] && chest="0.62 0.13"   # its chin sits low
  # shellcheck disable=SC2086
  BOXES_FROM="$RIGSRC" "$TMP/companion_cut" "$CLEAN" "$f" "$TMP/$f" 1.3 $chest >/dev/null
  mkdir -p "$TMP/swap-$f"
  for n in 1 2 3 4 5 6 7; do
    cp "$TMP/$f/body-$n.png" "$TMP/swap-$f/$f-body-$n.png"
    cp "$TMP/$f/chest-$n.png" "$TMP/swap-$f/$f-chest-$n.png"
    # boxes.txt is in canvas units; the body crop starts at x*1.3, y*1.3
    read -r bx by <<<"$(awk -v k="body-$n" '$1 == k { printf "%.0f %.0f", $2 * 1.3, $3 * 1.3 }' "$TMP/$f/boxes.txt")"
    polish "$TMP/swap-$f/$f-body-$n.png" 0.65 "$bx" "$by" &
  done
  wait
  python3 tools/riv_images.py replace "Coherence/Otto/Companion$key.riv" "$TMP/Companion$key.riv" "$TMP/swap-$f"
  mv "$TMP/Companion$key.riv" "Coherence/Otto/Companion$key.riv"
done
rm -rf "$TMP"
echo done
