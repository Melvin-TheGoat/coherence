#!/usr/bin/env python3
"""Split the waving pose into a body layer and an arm layer that can rotate.

    python3 tools/otto_cut_arm.py --preview             # look before writing
    python3 tools/otto_cut_arm.py
    python3 tools/otto_cut_arm.py --pose sit-wave       # the seated greeting

WHY A CUT AND NOT BONES: the Rive tool can bind a mesh to bones and weight
it, but its auto-weight puts every vertex on the root bone no matter where
the bones sit (288 of 289, measured, and unchanged by moving the root 200
units). So a skinned arm cannot be produced from here. A separate arm image
rotating about the shoulder is what most 2D mascot rigs do for a wave
anyway, and every frame of it can be checked.

THE CUT is a POLYLINE that SEVERS, not a half plane. A half plane was tried
first and takes the head with the arm, because the arm has body on one side
and head on the other. So: erase a thin band along the line, then keep the
connected island that contains the hand. The line runs from the gap between
the hand and the cheek, down through the forearm, into the background below
the arm. It takes several points because an arm held against the body is
enclosed by the torso: the seated greeting needs to follow the arm's own
contour down and then break out at the bottom left, which no straight line
can do.

IT DELIBERATELY OVERLAPS. The arm keeps a band of pixels past the cut line
(`OVERLAP`), and the arm is drawn ON TOP of the body, so when it rotates a
few degrees the joint stays covered instead of opening a hole. That band is
the whole reason the seam does not show, and it is why the rotation has to
stay small: past about ten degrees the overlap runs out.

THE OVERLAP IS FEATHERED (`FEATHER`). A hard-edged band is invisible at
rest and then swings out from behind the head as a straight diagonal lip
the moment the arm turns, which is exactly what it looked like on the
seated greeting at 12 degrees. Fading the outer part of the band to
nothing hands the pixels over to the body underneath, which is the same
fur, so the join reads as shading rather than as a cut.

The pivot is written to pivot.json beside the layers, in pixels of the
original pose, so the Rive side does not have to re-derive it.
"""

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from otto_split import read_png, write_png  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "mockups", "otto-v3")

# Per pose, because the geometry is the pose's own and nothing about it
# transfers: `cut` is two points on the severing line (A up in the gap
# between the hand and the head, B out past the shoulder into the
# background), `band` how thick a line to erase, `overlap` how far the arm
# grows back across the cut so the joint stays covered, `seed` a pixel that
# is certainly on the hand, and `pivot` where the arm turns.
POSES = {
    "wave": dict(src="otto-wave.png", out="otto-wave",
                 a=(122.0, 196.0), b=(34.0, 306.0), band=5.0, overlap=26.0,
                 feather=0.0,
                 seed=(62.0, 150.0), pivot=(95.0, 245.0),
                 min_island=4000, min_body=20000),
    "sit-wave": dict(src="otto-sit-wave.png", out="otto-sit-wave",
                     points=[(54.0, 138.0), (92.0, 250.0), (60.0, 318.0), (18.0, 344.0)],
                     band=5.0, overlap=30.0, feather=0.7,
                     seed=(40.0, 170.0), pivot=(78.0, 250.0),
                     min_island=3000, min_body=20000),
}

_which = "wave"
if "--pose" in sys.argv:
    _which = sys.argv[sys.argv.index("--pose") + 1]
if _which not in POSES:
    sys.exit("unknown pose %r; try one of %s" % (_which, ", ".join(POSES)))
_P = POSES[_which]

SRC = os.path.join(REPO, "mockups", "otto-v3", _P["src"])
STEM = _P["out"]
# Either two named endpoints or a polyline; both become a list of points.
CUT = _P.get("points") or [_P["a"], _P["b"]]
CUT_A, CUT_B = CUT[0], CUT[-1]
BAND, OVERLAP = _P["band"], _P["overlap"]
# Fraction of the overlap band that fades out. 0 keeps the old hard edge.
FEATHER = _P.get("feather", 0.0)
SEED, PIVOT = _P["seed"], _P["pivot"]
MIN_ISLAND, MIN_BODY = _P["min_island"], _P["min_body"]


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


def on_polyline(p, pts):
    """Distance from the nearest segment of the cut."""
    return min(on_segment(p, pts[i], pts[i + 1]) for i in range(len(pts) - 1))


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
            if ink[i] and on_polyline((x + 0.5, y + 0.5), CUT) <= BAND / 2.0:
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

    # How opaque each overlap pixel stays. Solid across the island and the
    # inner band, then a linear fade to nothing at the outer edge.
    def keep(i):
        if FEATHER <= 0:
            return 1.0
        d = dist.get(i, 0)
        if d == 0:
            return 1.0
        solid = OVERLAP * (1.0 - FEATHER)
        if d <= solid:
            return 1.0
        t = (d - solid) / max(1e-6, OVERLAP - solid)
        return max(0.0, 1.0 - t)

    arm = bytearray(w * h * 4)
    body = bytearray(w * h * 4)
    n_arm = n_body = 0
    for i in range(w * h):
        o = i * 4
        if not ink[i]:
            continue
        if arm_mask[i]:
            arm[o:o + 4] = px[o:o + 4]
            k = keep(i)
            if k < 1.0:
                arm[o + 3] = int(px[o + 3] * k)
            n_arm += 1
        if not comp[i]:
            body[o:o + 4] = px[o:o + 4]
            n_body += 1

    print("pose %dx%d  island %d px  arm with overlap %d px  body %d px"
          % (w, h, n_comp, n_arm, n_body))
    if n_comp < MIN_ISLAND or n_body < MIN_BODY:
        sys.exit("That cut does not look like an arm and a body. Move CUT_A / CUT_B.")

    suffix = "-preview" if preview else ""
    for name, buf in (("arm", arm), ("body", body)):
        path = os.path.join(OUT, "%s-%s%s.png" % (STEM, name, suffix))
        write_png(path, w, h, buf)
        print("wrote %s" % os.path.relpath(path, REPO))
    if not preview:
        with open(os.path.join(OUT, "%s-pivot.json" % STEM), "w") as fh:
            json.dump({"pose": os.path.basename(SRC), "width": w, "height": h,
                       "pivot": {"x": PIVOT[0], "y": PIVOT[1]},
                       "cut": {"points": CUT, "band": BAND,
                               "overlap": OVERLAP, "seed": SEED}}, fh, indent=2)
        print("wrote mockups/otto-v3/%s-pivot.json" % STEM)


if __name__ == "__main__":
    main()
