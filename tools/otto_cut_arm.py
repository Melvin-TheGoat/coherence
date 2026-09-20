#!/usr/bin/env python3
"""Split the waving pose into a body layer and an arm layer that can rotate.

    python3 tools/otto_cut_arm.py --preview      # look before writing
    python3 tools/otto_cut_arm.py

WHY A CUT AND NOT BONES: the Rive tool can bind a mesh to bones and weight
it, but its auto-weight puts every vertex on the root bone no matter where
the bones sit (288 of 289, measured, and unchanged by moving the root 200
units). So a skinned arm cannot be produced from here. A separate arm image
rotating about the shoulder is what most 2D mascot rigs do for a wave
anyway, and every frame of it can be checked.

THE CUT is a line that SEVERS, not a half plane. A half plane was tried
first and takes the head with the arm, because the arm has body on one side
and head on the other. So: erase a thin band along the line, then keep the
connected island that contains the hand. The line runs from the gap between
the hand and the cheek, down through the forearm, into the background below
the arm.

IT DELIBERATELY OVERLAPS. The arm keeps a band of pixels past the cut line
(`OVERLAP`), and the arm is drawn ON TOP of the body, so when it rotates a
few degrees the joint stays covered instead of opening a hole. That band is
the whole reason the seam does not show, and it is why the rotation has to
stay small: past about ten degrees the overlap runs out.

The pivot is written to pivot.json beside the layers, in pixels of the
original pose, so the Rive side does not have to re-derive it.
"""

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from otto_split import read_png, write_png  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(REPO, "mockups", "otto-v3", "otto-wave.png")
OUT = os.path.join(REPO, "mockups", "otto-v3")

# Two points on the cut line, in the pose's pixels. A is up in the gap
# between the hand and the head; B is below the shoulder.
CUT_A = (122.0, 196.0)
CUT_B = (34.0, 306.0)
# Thickness of the band erased to sever the arm.
BAND = 5.0
# The arm keeps this many pixels past the cut, so the joint stays covered.
OVERLAP = 26.0
# A point that is definitely on the hand, used to pick the severed island.
SEED = (62.0, 150.0)
# Where the arm turns, in the pose's pixels: the middle of the cut.
PIVOT = (95.0, 245.0)


def side(p, a, b):
    """Signed distance from the line ab."""
    (x, y), (ax, ay), (bx, by) = p, a, b
    dx, dy = bx - ax, by - ay
    n = (dx * dx + dy * dy) ** 0.5
    return ((x - ax) * dy - (y - ay) * dx) / n


def on_segment(p, a, b):
    """Distance from the SEGMENT ab, so the band does not run on forever."""
    (x, y), (ax, ay), (bx, by) = p, a, b
    dx, dy = bx - ax, by - ay
    L2 = dx * dx + dy * dy
    t = max(0.0, min(1.0, ((x - ax) * dx + (y - ay) * dy) / L2))
    cx, cy = ax + t * dx, ay + t * dy
    return ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5


def main():
    preview = "--preview" in sys.argv
    w, h, px = read_png(SRC)
    ink = bytearray(w * h)
    for i in range(w * h):
        ink[i] = 1 if px[i * 4 + 3] > 24 else 0

    # Cut the band, then take the island holding the hand.
    cut = bytearray(w * h)
    for y in range(h):
        for x in range(w):
            i = y * w + x
            if ink[i] and on_segment((x + 0.5, y + 0.5), CUT_A, CUT_B) <= BAND / 2.0:
                cut[i] = 1

    sx, sy = SEED
    seed = int(sy) * w + int(sx)
    if not ink[seed] or cut[seed]:
        sys.exit("The seed %s is not on the arm. Move SEED." % (SEED,))
    comp = bytearray(w * h)
    stack = [seed]
    comp[seed] = 1
    while stack:
        i = stack.pop()
        x, y = i % w, i // w
        for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if 0 <= nx < w and 0 <= ny < h:
                j = ny * w + nx
                if ink[j] and not cut[j] and not comp[j]:
                    comp[j] = 1
                    stack.append(j)
    n_comp = sum(comp)

    # Grow the arm back across the cut by OVERLAP, so the joint stays
    # covered when it turns. Bounded flood, so it cannot run off into the
    # torso further than asked.
    dist = {}
    frontier = []
    for i in range(w * h):
        if comp[i]:
            frontier.append(i)
            dist[i] = 0
    step = 0
    while frontier and step < int(OVERLAP):
        step += 1
        nxt = []
        for i in frontier:
            x, y = i % w, i // w
            for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                if 0 <= nx < w and 0 <= ny < h:
                    j = ny * w + nx
                    if ink[j] and j not in dist:
                        dist[j] = step
                        nxt.append(j)
        frontier = nxt
    arm_mask = bytearray(w * h)
    for i in dist:
        arm_mask[i] = 1

    arm = bytearray(w * h * 4)
    body = bytearray(w * h * 4)
    n_arm = n_body = 0
    for i in range(w * h):
        o = i * 4
        if not ink[i]:
            continue
        if arm_mask[i]:
            arm[o:o + 4] = px[o:o + 4]
            n_arm += 1
        if not comp[i]:
            body[o:o + 4] = px[o:o + 4]
            n_body += 1

    print("pose %dx%d  island %d px  arm with overlap %d px  body %d px"
          % (w, h, n_comp, n_arm, n_body))
    if n_comp < 4000 or n_body < 20000:
        sys.exit("That cut does not look like an arm and a body. Move CUT_A / CUT_B.")

    suffix = "-preview" if preview else ""
    for name, buf in (("arm", arm), ("body", body)):
        path = os.path.join(OUT, "otto-wave-%s%s.png" % (name, suffix))
        write_png(path, w, h, buf)
        print("wrote %s" % os.path.relpath(path, REPO))
    if not preview:
        with open(os.path.join(OUT, "arm-pivot.json"), "w") as fh:
            json.dump({"pose": os.path.basename(SRC), "width": w, "height": h,
                       "pivot": {"x": PIVOT[0], "y": PIVOT[1]},
                       "cut": {"a": CUT_A, "b": CUT_B, "band": BAND,
                               "overlap": OVERLAP, "seed": SEED}}, fh, indent=2)
        print("wrote mockups/otto-v3/arm-pivot.json")


if __name__ == "__main__":
    main()
