#!/usr/bin/env python3
"""List, extract or replace the images embedded in a runtime .riv, without the editor.

    python3 tools/riv_images.py list    in.riv
    python3 tools/riv_images.py extract in.riv OUTDIR            # OUTDIR/<asset name>.png
    python3 tools/riv_images.py replace in.riv out.riv DIR       # DIR/<asset name>.png replaces each

Written 2026-11-13 to take the white paper out of the companions' rig bodies
when the Rive editor had no file open (its MCP cannot open or switch files).
A .riv is a flat list of objects with no offset table, so an embedded image is
one length-prefixed bytes property (FileAssetContents) after its ImageAsset,
and swapping it changes nothing else in the file. `replace` refuses any image
whose pixel size differs from the asset's recorded width and height, so the
rig's placement (and the hats and rig numbers built on it) stays exact. It
re-reads the written file and checks every object, property and byte outside
the swapped images is unchanged.
"""
import os, struct, sys, zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))


def varuint(b, p):
    r = s = 0
    while True:
        c = b[p]; p += 1
        r |= (c & 0x7f) << s; s += 7
        if c < 0x80:
            return r, p


def enc(v):
    out = bytearray()
    while True:
        c = v & 0x7f; v >>= 7
        if v:
            out.append(c | 0x80)
        else:
            out.append(c); return bytes(out)


def png_size(data):
    assert data[:8] == b"\x89PNG\r\n\x1a\n", "not a PNG"
    return struct.unpack(">II", data[16:24])


def scan(path):
    """Yields (assetName, width, height, start, end) for each embedded image's bytes property,
    where data[start:end] is the varuint length plus the bytes."""
    import riv_dump
    b = open(path, "rb").read()
    # Re-walk the file the way riv_dump does, but keep byte offsets.
    p = 4
    for _ in range(3):
        _, p = varuint(b, p)
    keys = []
    while True:
        k, p = varuint(b, p)
        if k == 0:
            break
        keys.append(k)
    ftype = {}
    bit = 0; cur = 0
    for k in keys:
        if bit == 0:
            cur = struct.unpack_from("<I", b, p)[0]; p += 4
        ftype[k] = (cur >> bit) & 3
        bit += 2
        if bit == 32:
            bit = 0
    found, asset = [], None
    while p < len(b):
        tk, p = varuint(b, p)
        t = riv_dump.types.get(tk, str(tk))
        props = {}
        while True:
            k, p = varuint(b, p)
            if k == 0:
                break
            ct = riv_dump.coretype.get(k)
            ft = {"CoreUintType": 0, "CoreIdType": 0, "CoreIntType": 0, "CoreStringType": 1, "CoreBytesType": 1,
                  "CoreDoubleType": 2, "CoreColorType": 3, "CoreBoolType": 4}.get(ct, ftype.get(k))
            name = riv_dump.props.get(k, (None, str(k)))[1]
            if ft == 0:
                v, p = varuint(b, p)
            elif ft == 1:
                start = p
                n, p = varuint(b, p)
                v = b[p:p + n]; p += n
                if t == "FileAssetContents" and asset is not None:
                    found.append((asset["name"], asset.get("width"), asset.get("height"), start, p))
                    asset = None
                elif t != "FileAssetContents":
                    try:
                        v = v.decode()
                    except Exception:
                        pass
            elif ft == 2:
                v = struct.unpack_from("<f", b, p)[0]; p += 4
            elif ft == 3:
                v = struct.unpack_from("<I", b, p)[0]; p += 4
            elif ft == 4:
                v = b[p] == 1; p += 1
            else:
                raise SystemExit("unknown property %s in %s" % (k, t))
            props[name] = v
        if t == "ImageAsset":
            asset = props
    return b, found


def main():
    cmd, path = sys.argv[1], sys.argv[2]
    b, found = scan(path)
    if cmd == "list":
        for name, w, h, s, e in found:
            n, q = varuint(b, s)
            print("%-22s %4dx%-4d %8d bytes  png %s" % (name, w or 0, h or 0, n, "%dx%d" % png_size(b[q:e])))
    elif cmd == "extract":
        out = sys.argv[3]; os.makedirs(out, exist_ok=True)
        for name, w, h, s, e in found:
            n, q = varuint(b, s)
            open(os.path.join(out, name + ".png"), "wb").write(b[q:e])
        print("extracted %d images to %s" % (len(found), out))
    elif cmd == "replace":
        dst, src = sys.argv[3], sys.argv[4]
        out = bytearray(); last = 0; swapped = []
        for name, w, h, s, e in found:
            f = os.path.join(src, name + ".png")
            if not os.path.exists(f):
                continue
            data = open(f, "rb").read()
            pw, ph = png_size(data)
            n, q = varuint(b, s)
            ow, oh = png_size(b[q:e])
            if (pw, ph) != (ow, oh):
                raise SystemExit("%s is %dx%d, the rig's is %dx%d: refusing" % (name, pw, ph, ow, oh))
            out += b[last:s] + enc(len(data)) + data
            last = e; swapped.append(name)
        out += b[last:]
        open(dst, "wb").write(out)
        # Check: same objects, same images except the swapped ones.
        b2, found2 = scan(dst)
        assert [x[0] for x in found2] == [x[0] for x in found], "asset list changed"
        prev = 0; prev2 = 0
        for (n1, _, _, s1, e1), (n2, _, _, s2, e2) in zip(found, found2):
            assert b[prev:s1] == b2[prev2:s2], "bytes outside the images changed before %s" % n1
            if n1 not in swapped:
                assert b[s1:e1] == b2[s2:e2]
            prev, prev2 = e1, e2
        assert b[prev:] == b2[prev2:]
        print("swapped %d images into %s: %s" % (len(swapped), dst, " ".join(swapped)))


if __name__ == "__main__":
    main()
