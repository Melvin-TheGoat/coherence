#!/usr/bin/env python3
"""Cut a feathered chest patch out of a pose, so Rive can breathe with it.

    python3 tools/otto_chest.py --preview     # draw the ellipse on the pose
    python3 tools/otto_chest.py               # write the patches

WHY A PATCH. The first Breathe timeline scaled the WHOLE body 3.5 percent
from the feet, which reads as the picture zooming rather than a body
breathing: a real breath moves the chest and belly and leaves the head and
the feet more or less where they are. Melvin, 2026-09-20: "make it seem like
hes breathing naturally from his chest".

Rive cannot deform part of an image without a mesh, and the mesh route is
closed here (auto-weighting puts every vertex on the root bone; see
CLAUDE.md). So the chest becomes its OWN image, drawn on top of the pose and
scaled a few percent about its own centre. The patch keeps the pose's FULL
CANVAS with everything outside the ellipse erased, which is what makes it
line up: same size, same position, no arithmetic in the editor.

THE FEATHER IS THE WHOLE TRICK. A hard-edged patch scaled 3 percent shows
its rim as a seam, because the pixels inside it have moved and the pixels
just outside have not. Alpha that falls off over `FEATHER` pixels hides the
handover: the middle of the chest moves the most and is fully opaque, and by
the time the patch is half transparent it has barely moved at all.

The ellipse stays INSIDE the silhouette on purpose. A patch that includes
the body's outline would carry that outline outward when it scales and draw
a halo of body colour outside the real edge, against the transparent
background where nothing hides it.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from otto_split import read_png, write_png  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ART = os.path.join(REPO, "mockups", "otto-v3")

# (source, output, centre x, centre y, radius x, radius y) in the pose's own
# pixels, measured off the art. The wave pose is 409x507, the sit 398x474.
POSES = [
    ("otto-wave-body.png", "otto-wave-chest.png", 247, 330, 86, 96),
    ("otto-sit.png",       "otto-sit-chest.png",  198, 296, 74, 72),
    # The seated greeting. Cut from the BODY layer, not the whole pose: the
    # arm is its own image that rotates, and a patch carrying part of it
    # would swell the arm too.
    ("otto-sit-wave-body.png", "otto-sit-wave-chest.png", 208, 312, 68, 66),
]
# Alpha falls from 1 to 0 across this many pixels, inside the ellipse.
FEATHER = 46.0


def patch(px, w, h, cx, cy, rx, ry):
    out = bytearray(w * h * 4)
    # Feather in ellipse-normalised space, so the falloff is even all round.
    inner = 1.0 - FEATHER / min(rx, ry)
    for y in range(h):
        dy = (y - cy) / ry
        if abs(dy) > 1.0:
            continue
        for x in range(w):
            dx = (x - cx) / rx
            d = (dx * dx + dy * dy) ** 0.5
            if d >= 1.0:
                continue
            k = 1.0 if d <= inner else (1.0 - d) / (1.0 - inner)
            # Smoothstep, so the handover has no visible shoulder.
            k = k * k * (3 - 2 * k)
            i = (y * w + x) * 4
            a = px[i + 3]
            if not a:
                continue
            out[i:i + 3] = px[i:i + 3]
            out[i + 3] = int(a * k)
    return out


def main():
    preview = "--preview" in sys.argv
    for src, dst, cx, cy, rx, ry in POSES:
        w, h, px = read_png(os.path.join(ART, src))
        if preview:
            shown = bytearray(px)
            for t in range(1440):
                import math
                a = t * math.pi / 720
                x, y = int(cx + rx * math.cos(a)), int(cy + ry * math.sin(a))
                if 0 <= x < w and 0 <= y < h:
                    i = (y * w + x) * 4
                    shown[i:i + 4] = bytes((255, 0, 0, 255))
            path = os.path.join(ART, dst.replace(".png", "-preview.png"))
            write_png(path, w, h, shown)
            print("preview %s  %dx%d  centre (%d,%d) radii (%d,%d)"
                  % (os.path.relpath(path, REPO), w, h, cx, cy, rx, ry))
            continue
        out = patch(px, w, h, cx, cy, rx, ry)
        opaque = sum(1 for i in range(w * h) if out[i * 4 + 3] > 8)
        path = os.path.join(ART, dst)
        write_png(path, w, h, out)
        print("%s  %dx%d  %d px of chest  origin %.3f%%, %.3f%%"
              % (os.path.relpath(path, REPO), w, h, opaque,
                 cx * 100.0 / w, cy * 100.0 / h))


if __name__ == "__main__":
    main()
