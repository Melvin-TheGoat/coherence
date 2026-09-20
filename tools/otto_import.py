#!/usr/bin/env python3
"""Take a folder of new Otto drawings into the app.

    python3 tools/otto_import.py mockups/otto-v3
    python3 tools/otto_import.py mockups/otto-v3 --dest /tmp/try   # look first

Input: one transparent PNG per pose, named for the pose. Any resolution;
they are scaled here. Recognised names, and every place each one is seen:

    otto-wave    Home, and the waving art the Rive rig animates
    otto-sit     the session rows, the calendar, anywhere he is meditating
    otto-awake   avatars and list rows, eyes open, looking at you
    otto-head    the mark: the chat row, and anything under about 40pt
    otto-ask     clipboard in hand: the onboarding question screens
    otto-talk    optional. Without it the waving art stands in, which is
                 what ships today: the wave is the only open mouth we have.

Output: the Otto image sets in Shared/Assets.xcassets, at the sizes the app
already uses. **Every pose is normalised to a longest edge of 200 points**,
so they stand the same height, and @2x and @3x follow. That is what makes
a row of different poses look like one character rather than a character
and some friends.

It does NOT touch Otto.riv. The rig embeds its own copy of the art, so the
animated Otto is a separate step: tools/otto_swap.py, which wants the Rive
editor open.

A NOTE ON TRANSPARENCY, because it is the one thing that cannot be fixed
here: this Mac has no ImageMagick and no PIL, so nothing in the repo can
cut a background out. Ask the image model for a transparent background and
check it before running this. A pose on white will import as a white box.
"""

import json
import os
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from otto_split import read_png, write_png  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(REPO, "Shared", "Assets.xcassets")

# Source name -> image set name. Order is the order they are reported in.
POSES = [
    ("otto-wave", "OttoWave"),
    ("otto-sit", "OttoSit"),
    ("otto-awake", "OttoAwake"),
    ("otto-head", "OttoHead"),
    ("otto-ask", "OttoAsk"),
    ("otto-talk", "OttoTalk"),
]
# Longest edge in pixels per scale. @1x is 200 points; the rest follow.
SCALES = [("", 200), ("@2x", 400), ("@3x", 600)]


# The app icon is Otto's head on the app's own ground. Sampled off the icon
# that shipped: a vertical gradient from Sky at the top to Paper at the
# bottom, with the head filling the width and its chin running off the
# bottom edge. It has to be regenerated whenever the head is redrawn, or the
# home screen shows a different character from the app.
ICON = os.path.join(ASSETS, "AppIcon.appiconset", "AppIcon1024.png")
ICON_SIZE = 1024
ICON_TOP = (253, 237, 225)
ICON_BOTTOM = (253, 247, 237)
ICON_HEAD_TOP = 0.065      # where the crown starts, as a fraction of height
ICON_HEAD_WIDTH = 1.00     # head width as a fraction of the icon


def make_icon(head_png):
    """Compose AppIcon1024.png from the head pose. Opaque, as Apple requires."""
    scaled = os.path.join(os.path.dirname(ICON), ".head-scaled.png")
    subprocess.run(["sips", "--resampleWidth", str(int(ICON_SIZE * ICON_HEAD_WIDTH)),
                    head_png, "--out", scaled], capture_output=True, check=True)
    hw, hh, hp = read_png(scaled)
    os.remove(scaled)

    n = ICON_SIZE
    out = bytearray(n * n * 3)
    for y in range(n):
        t = y / float(n - 1)
        row = bytes(int(round(ICON_TOP[c] + (ICON_BOTTOM[c] - ICON_TOP[c]) * t))
                    for c in range(3)) * n
        out[y * n * 3:(y + 1) * n * 3] = row

    ox = (n - hw) // 2
    oy = int(n * ICON_HEAD_TOP)
    for y in range(hh):
        ty = oy + y
        if ty < 0 or ty >= n:
            continue
        for x in range(hw):
            tx = ox + x
            if tx < 0 or tx >= n:
                continue
            s = (y * hw + x) * 4
            a = hp[s + 3]
            if not a:
                continue
            d = (ty * n + tx) * 3
            if a == 255:
                out[d:d + 3] = hp[s:s + 3]
            else:
                f = a / 255.0
                for c in range(3):
                    out[d + c] = int(round(hp[s + c] * f + out[d + c] * (1 - f)))
    write_png(ICON, n, n, out, channels=3)
    return hw, hh


def dims(path):
    out = subprocess.run(["sips", "-g", "pixelWidth", "-g", "pixelHeight", path],
                         capture_output=True, text=True, check=False).stdout
    w = h = 0
    for line in out.splitlines():
        if "pixelWidth:" in line:
            w = int(line.split(":")[1])
        if "pixelHeight:" in line:
            h = int(line.split(":")[1])
    return w, h


def has_alpha(path):
    out = subprocess.run(["sips", "-g", "hasAlpha", path],
                         capture_output=True, text=True, check=False).stdout
    return "yes" in out


def contents_json(name):
    return json.dumps({
        "images": [{"idiom": "universal",
                    "filename": "%s%s.png" % (name, suffix),
                    "scale": "%sx" % (suffix[1:2] or "1")}
                   for suffix, _ in SCALES],
        "info": {"author": "xcode", "version": 1},
    }, indent=2) + "\n"


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if not args:
        sys.exit(__doc__.strip().splitlines()[2].strip())
    src = os.path.abspath(args[0])
    dest = ASSETS
    if "--dest" in sys.argv:
        dest = os.path.abspath(sys.argv[sys.argv.index("--dest") + 1])
    if not os.path.isdir(src):
        sys.exit("No such folder: %s" % src)

    found = {}
    for stem, setname in POSES:
        path = os.path.join(src, stem + ".png")
        if os.path.exists(path):
            found[stem] = path
    if not found:
        sys.exit("Nothing to import. Expected files named %s in %s."
                 % (", ".join(s + ".png" for s, _ in POSES), src))

    # The wave stands in for talking until there is real talking art. Recorded
    # in the 09-20 redesign commit: the wave is the only pose with an open
    # mouth, which is the thing `talking` is for.
    if "otto-talk" not in found and "otto-wave" in found:
        found["otto-talk"] = found["otto-wave"]
        print("otto-talk:  not supplied, using the waving art (as today)")

    flat = [p for p in found.values()]
    opaque = [os.path.basename(p) for p in set(flat) if not has_alpha(p)]
    if opaque:
        sys.exit("These have no transparency and would import as a box: %s\n"
                 "Ask the image model for a transparent background, or cut it "
                 "before running this." % ", ".join(sorted(opaque)))

    print("from:       %s" % src)
    print("to:         %s" % dest)
    for stem, setname in POSES:
        if stem not in found:
            print("%-11s skipped, no file" % (stem + ":"))
            continue
        source = found[stem]
        w, h = dims(source)
        folder = os.path.join(dest, setname + ".imageset")
        os.makedirs(folder, exist_ok=True)
        for suffix, edge in SCALES:
            out = os.path.join(folder, "%s%s.png" % (setname, suffix))
            # -Z fits the LONGEST edge, which for an upright pose is its
            # height. That is the existing convention for these sets.
            subprocess.run(["sips", "-Z", str(edge), source, "--out", out],
                           capture_output=True, check=True)
        with open(os.path.join(folder, "Contents.json"), "w") as fh:
            fh.write(contents_json(setname))
        nw, nh = dims(os.path.join(folder, setname + "@3x.png"))
        print("%-11s %gx%g  ->  %s, @3x %gx%g" % (stem + ":", w, h, setname, nw, nh))

    if "otto-head" in found and dest == ASSETS and "--no-icon" not in sys.argv:
        hw, hh = make_icon(found["otto-head"])
        print("icon:       head at %dx%d on the app ground -> AppIcon1024.png" % (hw, hh))

    print("\nNext: build and look. For the ANIMATED Otto, open the Rive editor "
          "and run\n  python3 tools/otto_swap.py %s/otto-wave.png"
          % os.path.relpath(src, REPO))


if __name__ == "__main__":
    main()
