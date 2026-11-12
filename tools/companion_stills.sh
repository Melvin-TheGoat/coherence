#!/bin/bash
# Installs the companions' seven stills per form into the app, the widget and
# the Watch (2026-11-12), from the 664 x 744 previews in mockups/companions/
# (base y = 649, the canvas Otto's stills and every rig share).
#
#   tools/companion_stills.sh            # from the repo root
#
# App:    Coherence/Companions.xcassets/Companion<Form><n>   664 x 744 (rig fallback,
#         the ears drawn over a hat brim, Otto's forms, the rebirth)
# Widget: OttoWidget/Assets.xcassets/Widget<Form><n>          401 x 450 (WidgetOtto's size)
# Watch:  CoherenceWatch/Assets.xcassets/Watch<Form><n>       321 x 360 (WatchOtto's size)
set -euo pipefail
src=mockups/companions
app=Coherence/Companions.xcassets
mkdir -p "$app"
printf '{\n  "info" : {\n    "author" : "xcode",\n    "version" : 1\n  }\n}\n' > "$app/Contents.json"

contents() {
  printf '{\n  "images" : [\n    {\n      "filename" : "%s.png",\n      "idiom" : "universal"\n    }\n  ],\n  "info" : {\n    "author" : "xcode",\n    "version" : 1\n  }\n}\n' "$1"
}

put() { # catalog name source height
  local dir="$1/$2.imageset"
  mkdir -p "$dir"
  contents "$2" > "$dir/Contents.json"
  if [ "$4" = 744 ]; then cp "$3" "$dir/$2.png"; else sips -Z "$4" "$3" --out "$dir/$2.png" >/dev/null; fi
}

for pair in redpanda:RedPanda tiger:Tiger phoenix:Phoenix dragon:Dragon; do
  file=${pair%%:*}; key=${pair##*:}
  for n in 1 2 3 4 5 6 7; do
    put "$app" "Companion$key$n" "$src/$file-$n.png" 744
    put OttoWidget/Assets.xcassets "Widget$key$n" "$src/$file-$n.png" 450
    put CoherenceWatch/Assets.xcassets "Watch$key$n" "$src/$file-$n.png" 360
  done
done
echo done
