#!/usr/bin/env python3
"""Cut a sheet of Otto poses into one transparent PNG per pose.

    python3 tools/otto_split.py ~/Downloads/otto-sheet.png
    python3 tools/otto_split.py sheet.png --names wave,sit,awake,head,talk
    python3 tools/otto_split.py sheet.png --dry-run     # just report the cells

Image models return the whole set as one picture, and every round so far has
then been cut by hand. This does it, in pure Python: **there is no PIL and no
ImageMagick on this machine**, so the PNG is decoded and re-encoded here with
nothing but `zlib` and `struct`.

HOW IT FINDS THE POSES: by the transparency, not by guessing a grid. It
projects the alpha channel onto the rows to find bands of figures, then onto
the columns inside each band to find the figures in it, splitting only on
gaps wider than `--gap` (a percentage of the sheet's width, 4 by default).
That threshold is the one thing to turn if a cut comes out wrong: too low and
a pose splits from its own motion marks, too high and two poses merge.
`--dry-run` prints every cell it found with its size, which is the cheap way
to check before writing anything.

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


def read_png(path):
    """-> (width, height, bytearray of RGBA rows). 8-bit RGBA only."""
    with open(path, "rb") as fh:
        data = fh.read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        sys.exit("%s is not a PNG." % path)
    pos, idat, w = 8, [], None
    while pos < len(data):
        (length,) = struct.unpack(">I", data[pos:pos + 4])
        kind = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + length]
        if kind == b"IHDR":
            w, h, depth, colour, comp, filt, interlace = struct.unpack(">IIBBBBB", body)
            if depth != 8 or colour != 6:
                sys.exit("Need an 8 bit RGBA PNG (colour type 6, depth 8); this is "
                         "colour type %d at depth %d. Re-export it with transparency."
                         % (colour, depth))
            if interlace:
                sys.exit("Interlaced PNGs are not supported. Re-export without interlacing.")
        elif kind == b"IDAT":
            idat.append(body)
        elif kind == b"IEND":
            break
        pos += 12 + length
    if w is None:
        sys.exit("No IHDR in %s." % path)

    raw = zlib.decompress(b"".join(idat))
    stride = w * 4
    out = bytearray(h * stride)
    prev = bytearray(stride)
    pos = 0
    for y in range(h):
        ftype = raw[pos]
        pos += 1
        line = bytearray(raw[pos:pos + stride])
        pos += stride
        if ftype == 1:
            for i in range(4, stride):
                line[i] = (line[i] + line[i - 4]) & 0xFF
        elif ftype == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 0xFF
        elif ftype == 3:
            for i in range(stride):
                left = line[i - 4] if i >= 4 else 0
                line[i] = (line[i] + ((left + prev[i]) >> 1)) & 0xFF
        elif ftype == 4:
            for i in range(stride):
                left = line[i - 4] if i >= 4 else 0
                upleft = prev[i - 4] if i >= 4 else 0
                line[i] = (line[i] + _paeth(left, prev[i], upleft)) & 0xFF
        elif ftype != 0:
            sys.exit("Unknown PNG filter %d on row %d." % (ftype, y))
        out[y * stride:(y + 1) * stride] = line
        prev = line
    return w, h, out


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

def runs(occupied, min_gap):
    """Index ranges of True, joined across gaps shorter than `min_gap`."""
    spans, start = [], None
    for i, on in enumerate(occupied):
        if on and start is None:
            start = i
        elif not on and start is not None:
            spans.append([start, i])
            start = None
    if start is not None:
        spans.append([start, len(occupied)])
    if not spans:
        return []
    merged = [spans[0]]
    for lo, hi in spans[1:]:
        if lo - merged[-1][1] < min_gap:
            merged[-1][1] = hi
        else:
            merged.append([lo, hi])
    return merged


def alpha_at(pixels, w, x, y):
    return pixels[(y * w + x) * 4 + 3]


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if not args:
        sys.exit("Give me the sheet: python3 tools/otto_split.py <sheet.png>")
    sheet = os.path.abspath(args[0])
    dry = "--dry-run" in sys.argv
    gap_pct = 4.0
    if "--gap" in sys.argv:
        gap_pct = float(sys.argv[sys.argv.index("--gap") + 1])
    names = DEFAULT_NAMES
    if "--names" in sys.argv:
        names = [n.strip() for n in sys.argv[sys.argv.index("--names") + 1].split(",")]
    out_dir = os.path.join(REPO, "mockups", "otto-v3")
    if "--out" in sys.argv:
        out_dir = os.path.abspath(sys.argv[sys.argv.index("--out") + 1])

    w, h, px = read_png(sheet)
    print("sheet:  %s  %dx%d" % (os.path.basename(sheet), w, h))
    min_gap = max(4, int(w * gap_pct / 100.0))

    # A pixel counts as ink above this alpha. Soft edges and near-invisible
    # compression noise should not widen a bounding box.
    INK = 24
    row_has = [False] * h
    col_of_row = []
    for y in range(h):
        base = y * w * 4
        cols = [x for x in range(w) if px[base + x * 4 + 3] > INK]
        col_of_row.append(cols)
        row_has[y] = bool(cols)

    cells = []
    for top, bottom in runs(row_has, min_gap):
        occupied = [False] * w
        for y in range(top, bottom):
            for x in col_of_row[y]:
                occupied[x] = True
        for left, right in runs(occupied, min_gap):
            # Tighten vertically inside this column, so a short pose in a tall
            # band is not padded with the band's empty rows.
            ys = [y for y in range(top, bottom)
                  if any(left <= x < right for x in col_of_row[y])]
            cells.append((left, min(ys), right, max(ys) + 1))

    if len(cells) != len(names):
        print("\nFound %d cells but %d names (%s)." % (len(cells), len(names), ", ".join(names)))
        print("Turn --gap (now %.1f%% of width) or pass --names to match." % gap_pct)
    for i, (x0, y0, x1, y1) in enumerate(cells):
        label = names[i] if i < len(names) else "cell%d" % (i + 1)
        print("  %-7s %4dx%-4d at (%d, %d)" % (label, x1 - x0, y1 - y0, x0, y0))
    if dry:
        print("\ndry run, nothing written.")
        return
    if len(cells) != len(names):
        sys.exit("\nRefusing to write a set that does not match the names.")

    os.makedirs(out_dir, exist_ok=True)
    for (x0, y0, x1, y1), name in zip(cells, names):
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
