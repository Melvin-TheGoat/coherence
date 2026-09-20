#!/usr/bin/env python3
"""Cut a sheet of Otto poses into one transparent PNG per pose.

    python3 tools/otto_split.py ~/Downloads/otto-sheet.png
    python3 tools/otto_split.py sheet.png --names wave,sit,awake,head,talk
    python3 tools/otto_split.py sheet.png --dry-run     # just report the cells

Image models return the whole set as one picture, and every round so far has
then been cut by hand. This does it, in pure Python: **there is no PIL and no
ImageMagick on this machine**, so the PNG is decoded and re-encoded here with
nothing but `zlib` and `struct`.

HOW IT FINDS THE POSES: by the transparency, not by guessing a grid, and by
ISLANDS rather than by projecting rows and columns. Projection was tried
first and cannot work on a real sheet: the poses sat 18 pixels apart
vertically while the little motion marks sat 30 pixels from the arm they
belong to, so no single gap both separates the rows and keeps a pose whole.

So: every island of opaque pixels is found, the big ones are the poses, and
each small one is absorbed into the nearest pose within `--absorb` (a
percentage of the sheet's width, 8 by default). That is what keeps the
yellow dashes with the waving arm. A stray further away than that is
reported and left out. `--dry-run` prints every pose it found with its size
and what it absorbed, which is the cheap way to check before writing.

Each pose is written cropped to its own opaque bounds, which is what the app
wants: `tools/otto_import.py` normalises every pose to the same height, so a
crop with slack around it comes out smaller than its neighbours.

Reading order is left to right, top to bottom, and `--names` maps onto that
order. The default is the five poses the brief asks for.
"""

import os
import struct
import sys
import zlib

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_NAMES = ["wave", "sit", "awake", "head", "talk"]


# ---------------------------------------------------------------- PNG codec

def _paeth(a, b, c):
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    return b if pb <= pc else c


def read_png_any(path):
    """-> (width, height, pixels, channels). Accepts 8 bit RGB or RGBA.

    RGB is accepted because a flattened export arrives that way, and
    tools/otto_unmatte.py has to read one in order to give it an alpha
    channel back. Everything downstream wants 4 channels.
    """
    with open(path, "rb") as fh:
        data = fh.read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        sys.exit("%s is not a PNG." % path)
    pos, idat, w, channels = 8, [], None, 4
    while pos < len(data):
        (length,) = struct.unpack(">I", data[pos:pos + 4])
        kind = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + length]
        if kind == b"IHDR":
            w, h, depth, colour, comp, filt, interlace = struct.unpack(">IIBBBBB", body)
            if depth != 8 or colour not in (2, 6):
                sys.exit("Need an 8 bit RGB or RGBA PNG (colour type 2 or 6, depth 8); "
                         "this is colour type %d at depth %d." % (colour, depth))
            if interlace:
                sys.exit("Interlaced PNGs are not supported. Re-export without interlacing.")
            channels = 4 if colour == 6 else 3
        elif kind == b"IDAT":
            idat.append(body)
        elif kind == b"IEND":
            break
        pos += 12 + length
    if w is None:
        sys.exit("No IHDR in %s." % path)

    raw = zlib.decompress(b"".join(idat))
    ch = channels
    stride = w * ch
    out = bytearray(h * stride)
    prev = bytearray(stride)
    pos = 0
    for y in range(h):
        ftype = raw[pos]
        pos += 1
        line = bytearray(raw[pos:pos + stride])
        pos += stride
        if ftype == 1:
            for i in range(ch, stride):
                line[i] = (line[i] + line[i - ch]) & 0xFF
        elif ftype == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 0xFF
        elif ftype == 3:
            for i in range(stride):
                left = line[i - ch] if i >= ch else 0
                line[i] = (line[i] + ((left + prev[i]) >> 1)) & 0xFF
        elif ftype == 4:
            for i in range(stride):
                left = line[i - ch] if i >= ch else 0
                upleft = prev[i - ch] if i >= ch else 0
                line[i] = (line[i] + _paeth(left, prev[i], upleft)) & 0xFF
        elif ftype != 0:
            sys.exit("Unknown PNG filter %d on row %d." % (ftype, y))
        out[y * stride:(y + 1) * stride] = line
        prev = line
    return w, h, out, ch


def read_png(path):
    """-> (width, height, RGBA bytes). Refuses a file with no alpha, because
    the poses are found BY their transparency: a flattened sheet would read
    as one big rectangle. tools/otto_unmatte.py restores alpha first."""
    w, h, px, ch = read_png_any(path)
    if ch != 4:
        sys.exit("%s has no alpha channel, so there is no transparency to find "
                 "the poses by.\nIf its background is a transparency "
                 "checkerboard, run:\n  python3 tools/otto_unmatte.py %s"
                 % (os.path.basename(path), path))
    return w, h, px


def write_png(path, w, h, pixels):
    """`pixels` is a bytearray of w*h*4. Written with filter 0 throughout:
    slightly bigger than an optimised encoder and perfectly valid."""
    stride = w * 4
    raw = bytearray()
    for y in range(h):
        raw.append(0)
        raw += pixels[y * stride:(y + 1) * stride]
    chunks = [(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)),
              (b"IDAT", zlib.compress(bytes(raw), 9)),
              (b"IEND", b"")]
    with open(path, "wb") as fh:
        fh.write(b"\x89PNG\r\n\x1a\n")
        for kind, body in chunks:
            fh.write(struct.pack(">I", len(body)))
            fh.write(kind + body)
            fh.write(struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF))


# ------------------------------------------------------------------ cutting

# A pixel counts as ink above this alpha. Soft edges and the faint remains of
# a de-matte should not widen a bounding box.
INK = 24


def islands(w, h, px):
    """Every connected run of ink, as (area, x0, y0, x1, y1). Iterative, so a
    figure the size of half a sheet cannot blow the stack."""
    seen = bytearray(w * h)
    found = []
    for start in range(w * h):
        if seen[start] or px[start * 4 + 3] <= INK:
            continue
        stack = [start]
        seen[start] = 1
        area = 0
        x0 = x1 = start % w
        y0 = y1 = start // w
        while stack:
            i = stack.pop()
            x, y = i % w, i // w
            area += 1
            if x < x0: x0 = x
            if x > x1: x1 = x
            if y < y0: y0 = y
            if y > y1: y1 = y
            for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1),
                           (x - 1, y - 1), (x + 1, y - 1), (x - 1, y + 1), (x + 1, y + 1)):
                if 0 <= nx < w and 0 <= ny < h:
                    j = ny * w + nx
                    if not seen[j] and px[j * 4 + 3] > INK:
                        seen[j] = 1
                        stack.append(j)
        found.append([area, x0, y0, x1 + 1, y1 + 1])
    return found


def box_gap(a, b):
    """Shortest distance between two boxes; 0 when they touch or overlap."""
    dx = max(0, max(a[1] - b[3], b[1] - a[3]))
    dy = max(0, max(a[2] - b[4], b[2] - a[4]))
    return (dx * dx + dy * dy) ** 0.5


def reading_order(figures):
    """Top to bottom, then left to right, with figures whose vertical spans
    overlap treated as one row. A sheet is read the way a page is."""
    rows, rest = [], sorted(figures, key=lambda f: f[2])
    for fig in rest:
        for row in rows:
            top = max(r[2] for r in row)
            bottom = min(r[4] for r in row)
            if min(bottom, fig[4]) - max(top, fig[2]) > 0:
                row.append(fig)
                break
        else:
            rows.append([fig])
    return [f for row in rows for f in sorted(row, key=lambda f: f[1])]


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if not args:
        sys.exit("Give me the sheet: python3 tools/otto_split.py <sheet.png>")
    sheet = os.path.abspath(args[0])
    dry = "--dry-run" in sys.argv
    absorb_pct = 8.0
    if "--absorb" in sys.argv:
        absorb_pct = float(sys.argv[sys.argv.index("--absorb") + 1])
    names = DEFAULT_NAMES
    if "--names" in sys.argv:
        names = [n.strip() for n in sys.argv[sys.argv.index("--names") + 1].split(",")]
    out_dir = os.path.join(REPO, "mockups", "otto-v3")
    if "--out" in sys.argv:
        out_dir = os.path.abspath(sys.argv[sys.argv.index("--out") + 1])

    w, h, px = read_png(sheet)
    print("sheet:  %s  %dx%d" % (os.path.basename(sheet), w, h))
    blobs = islands(w, h, px)
    if not blobs:
        sys.exit("Nothing opaque in that sheet.")
    biggest = max(b[0] for b in blobs)
    # A pose is within a factor of twenty of the largest. Motion marks and
    # de-matte crumbs are orders of magnitude smaller than that.
    figures = [b for b in blobs if b[0] >= biggest * 0.05]
    strays = [b for b in blobs if b[0] < biggest * 0.05]
    figures = reading_order(figures)

    reach = w * absorb_pct / 100.0
    adopted = [0] * len(figures)
    orphans = 0
    for stray in strays:
        near, best = None, reach
        for idx, fig in enumerate(figures):
            d = box_gap(stray, fig)
            if d <= best:
                near, best = idx, d
        if near is None:
            orphans += 1
            continue
        fig = figures[near]
        fig[1] = min(fig[1], stray[1])
        fig[2] = min(fig[2], stray[2])
        fig[3] = max(fig[3], stray[3])
        fig[4] = max(fig[4], stray[4])
        adopted[near] += 1

    if len(figures) != len(names):
        print("\nFound %d poses but %d names (%s)."
              % (len(figures), len(names), ", ".join(names)))
        print("Pass --names to match, or look at the sheet.")
    for i, fig in enumerate(figures):
        label = names[i] if i < len(names) else "pose%d" % (i + 1)
        extra = "  + %d mark%s" % (adopted[i], "" if adopted[i] == 1 else "s") if adopted[i] else ""
        print("  %-7s %4dx%-4d at (%d, %d)%s"
              % (label, fig[3] - fig[1], fig[4] - fig[2], fig[1], fig[2], extra))
    if orphans:
        print("  (%d stray bit%s too far from any pose, left out)"
              % (orphans, "" if orphans == 1 else "s"))
    if dry:
        print("\ndry run, nothing written.")
        return
    if len(figures) != len(names):
        sys.exit("\nRefusing to write a set that does not match the names.")

    os.makedirs(out_dir, exist_ok=True)
    for fig, name in zip(figures, names):
        _, x0, y0, x1, y1 = fig
        cw, ch = x1 - x0, y1 - y0
        crop = bytearray(cw * ch * 4)
        for y in range(ch):
            src = ((y0 + y) * w + x0) * 4
            crop[y * cw * 4:(y + 1) * cw * 4] = px[src:src + cw * 4]
        path = os.path.join(out_dir, "otto-%s.png" % name)
        write_png(path, cw, ch, crop)
        print("wrote:  %s" % os.path.relpath(path, REPO))
    print("\nNext:\n  python3 tools/otto_import.py %s" % os.path.relpath(out_dir, REPO))


if __name__ == "__main__":
    main()
