#!/usr/bin/env python3
"""Lift a flattened transparency checkerboard off a sheet and restore alpha.

    python3 tools/otto_unmatte.py ~/Downloads/slothmascot.png
    python3 tools/otto_unmatte.py sheet.png --out mockups/otto-v3/sheet.png

WHY THIS EXISTS: saving a generated image from a preview pane writes what
the pane DREW, and what it draws behind a transparent image is the grey and
white checkerboard. The file then has no alpha channel and a literal
checkerboard where the background should be. It happened on the third Otto
set (2026-09-20) and it will happen again, because the checkerboard looks
like transparency to anyone looking at it.

**Ask for the real transparent export first.** This reconstructs alpha, and
a reconstruction is never quite the original: edges that were drawn blended
against the checker can keep a faint light fringe. It is here so a flattened
file is a minor setback rather than a blocked afternoon.

HOW IT WORKS, and why it does not punch holes in a cream-coloured sloth:
the background is found by FLOODING IN FROM THE BORDER through pixels that
match a checker tone, so a white belly in the middle of a figure is never
reached and stays opaque. Only what is connected to the edge of the sheet
is removed. Then the pixels sitting between figure and background get a
partial alpha from how far their colour has moved off the checker, and are
un-premultiplied so the edge does not darken.

Pure Python: no PIL and no ImageMagick on this machine. It reads RGB or
RGBA and always writes RGBA.
"""

import os
import sys
from collections import deque

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from otto_split import read_png_any, write_png  # noqa: E402

# Background is anything NEAR-NEUTRAL and LIGHT that can be reached from the
# rim. Neutrality is what protects the art: this sloth is brown and cream,
# both well off grey, so nothing of him qualifies. Lightness is what lets the
# soft ground shadow go with the checker, since the shadow is a pale neutral
# grey a little darker than the checker and would otherwise survive as a
# smudge under his feet.
NEUTRAL_TOLERANCE = 8
SHADOW_FLOOR = 180
# How far a colour must move off the checker before it counts as fully
# opaque. Measured against this set: the character's own edge pixels clear
# it easily, and the checker's own 16 value step does not.
EDGE_SCALE = 45.0


def border_tones(w, h, px, ch):
    """The two most common near-neutral colours around the rim."""
    counts = {}
    for x in range(w):
        for y in (0, h - 1):
            o = (y * w + x) * ch
            counts[px[o]] = counts.get(px[o], 0) + 1
    for y in range(h):
        for x in (0, w - 1):
            o = (y * w + x) * ch
            counts[px[o]] = counts.get(px[o], 0) + 1
    ranked = sorted(counts.items(), key=lambda kv: -kv[1])
    tones = [v for v, _ in ranked[:2]]
    if len(tones) < 2:
        tones = tones * 2
    return sorted(tones)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if not args:
        sys.exit("Give me the sheet: python3 tools/otto_unmatte.py <sheet.png>")
    src = os.path.abspath(args[0])
    out = src
    if "--out" in sys.argv:
        out = os.path.abspath(sys.argv[sys.argv.index("--out") + 1])
    elif "--in-place" not in sys.argv:
        base, ext = os.path.splitext(src)
        out = base + "-alpha" + ext

    w, h, px, ch = read_png_any(src)
    print("sheet:   %s  %dx%d  %s" % (os.path.basename(src), w, h,
                                      "RGBA" if ch == 4 else "RGB"))
    lo, hi = border_tones(w, h, px, ch)
    print("checker: %d and %d" % (lo, hi))
    if hi - lo > 60:
        print("warning: those two tones are far apart. If this is not a "
              "checkerboard the result will be wrong; look before using it.")

    floor = SHADOW_FLOOR
    if "--floor" in sys.argv:
        floor = int(sys.argv[sys.argv.index("--floor") + 1])

    def is_tone(o):
        r, g, b = px[o], px[o + 1], px[o + 2]
        if max(r, g, b) - min(r, g, b) > NEUTRAL_TOLERANCE:
            return False
        return r >= floor

    # Flood in from every border pixel. Only background touching the rim is
    # removed, so enclosed light areas inside a figure survive.
    bg = bytearray(w * h)
    queue = deque()
    for x in range(w):
        for y in (0, h - 1):
            i = y * w + x
            if not bg[i] and is_tone(i * ch):
                bg[i] = 1
                queue.append(i)
    for y in range(h):
        for x in (0, w - 1):
            i = y * w + x
            if not bg[i] and is_tone(i * ch):
                bg[i] = 1
                queue.append(i)
    while queue:
        i = queue.popleft()
        x, y = i % w, i // w
        for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if 0 <= nx < w and 0 <= ny < h:
                j = ny * w + nx
                if not bg[j] and is_tone(j * ch):
                    bg[j] = 1
                    queue.append(j)

    removed = sum(bg)
    print("removed: %d background pixels (%.1f%% of the sheet)"
          % (removed, 100.0 * removed / (w * h)))
    if removed < w * h * 0.10:
        sys.exit("That is too little to be the background. Nothing written.")

    rgba = bytearray(w * h * 4)
    for i in range(w * h):
        o = i * ch
        r, g, b = px[o], px[o + 1], px[o + 2]
        if bg[i]:
            continue  # stays 0,0,0,0
        x, y = i % w, i // w
        # Average the background actually touching this pixel, rather than
        # assuming a checker tone: next to a shadow the local background is
        # the shadow, and un-premultiplying against the wrong colour is what
        # leaves a bright fringe.
        br = bgc = bb = 0
        touching = 0
        for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if 0 <= nx < w and 0 <= ny < h and bg[ny * w + nx]:
                no = (ny * w + nx) * ch
                br += px[no]
                bgc += px[no + 1]
                bb += px[no + 2]
                touching += 1
        d = i * 4
        if not touching:
            rgba[d], rgba[d + 1], rgba[d + 2], rgba[d + 3] = r, g, b, 255
            continue
        br /= touching
        bgc /= touching
        bb /= touching
        dist = max(abs(r - br), abs(g - bgc), abs(b - bb))
        a = min(1.0, dist / EDGE_SCALE)
        if a <= 0.02:
            continue
        # Un-premultiply against the tone it was blended with, so the edge
        # keeps its own colour instead of being lightened by the checker.
        inv = 1.0 - a
        fr = (r - inv * br) / a
        fg = (g - inv * bgc) / a
        fb = (b - inv * bb) / a
        rgba[d] = max(0, min(255, int(round(fr))))
        rgba[d + 1] = max(0, min(255, int(round(fg))))
        rgba[d + 2] = max(0, min(255, int(round(fb))))
        rgba[d + 3] = int(round(a * 255))

    write_png(out, w, h, rgba)
    print("wrote:   %s" % out)
    print("\nNext:\n  python3 tools/otto_split.py %s --dry-run" % out)


if __name__ == "__main__":
    main()
