#!/usr/bin/env python3
"""Read a runtime .riv (OttoAura.riv) without the Rive editor.

    python3 tools/riv_dump.py Coherence/Otto/OttoAura.riv            # Lift, Bob, Float
    python3 tools/riv_dump.py Coherence/Otto/OttoAura.riv --bodies DIR   # the 13 body PNGs

Written 2026-09-28 because the editor's cloud copy of OttoAura was OLDER than
the shipping file (no snap, no Leaves, no Halo layer), so its numbers could
not be trusted and nothing could be exported from it. The shipping file is
the truth: OttoAuraRig's lift, scale, body placement and Float curve, and
hat_extract's per-look masks (--looks), all come from here. The export strips
object names, so nodes are found by position: the figure at (332, 649), then
Lift, then Bob.
"""
import re, os, struct, sys, json
import glob
# The runtime's generated headers name every type and property and say how
# each is decoded. Any DerivedData or build folder with the rive-ios package
# checked out has them.
_cands = glob.glob("/tmp/*/SourcePackages/checkouts/rive-ios/submodules/rive-runtime/include/rive/generated") + \
    glob.glob(os.path.expanduser("~/808/build/*/SourcePackages/checkouts/rive-ios/submodules/rive-runtime/include/rive/generated")) + \
    glob.glob(os.path.expanduser("~/Library/Developer/Xcode/DerivedData/*/SourcePackages/checkouts/rive-ios/submodules/rive-runtime/include/rive/generated"))
RR = os.environ.get("RIVE_GENERATED") or (_cands[0] if _cands else "")
types, props, parent, coretype = {}, {}, {}, {}
for root, _, files in os.walk(RR):
    for f in files:
        if not f.endswith("_base.hpp"): continue
        t = open(os.path.join(root, f)).read()
        m = re.search(r"class (\w+)Base\s*:\s*public\s+([\w:]+)", t)
        if not m: continue
        cls = m.group(1)
        parent[cls] = m.group(2).split("::")[-1]
        tk = re.search(r"static const uint16_t typeKey = (\d+);", t)
        if tk: types[int(tk.group(1))] = cls
        local = {}
        for pm in re.finditer(r"static const uint16_t (\w+)PropertyKey = (\d+);", t):
            props[int(pm.group(2))] = (cls, pm.group(1)); local[pm.group(1)] = int(pm.group(2))
        for chunk in t.split("case ")[1:]:
            km = re.match(r"(\w+)PropertyKey:", chunk)
            cm = re.search(r"(Core\w+Type)::(?:runtime)?[dD]eserialize", chunk.split("return")[0])
            if km and cm and km.group(1) in local: coretype[local[km.group(1)]] = cm.group(1)

def load(path):
    b = open(path, "rb").read(); p = 0
    def vu():
        nonlocal p
        r = s = 0
        while True:
            c = b[p]; p += 1
            r |= (c & 0x7f) << s; s += 7
            if c < 0x80: return r
    assert b[:4] == b"RIVE"; p = 4
    vu(); vu(); vu()
    keys = []
    while True:
        k = vu()
        if k == 0: break
        keys.append(k)
    ftype = {}
    bit = 0; cur = 0
    for i, k in enumerate(keys):
        if bit == 0:
            cur = struct.unpack_from("<I", b, p)[0]; p += 4
        ftype[k] = (cur >> bit) & 3
        bit += 2
        if bit == 32: bit = 0
    objs = []
    while p < len(b):
        tk = vu()
        o = {"_t": types.get(tk, str(tk))}
        while True:
            k = vu()
            if k == 0: break
            ct = coretype.get(k)
            ft = {"CoreUintType": 0, "CoreIdType": 0, "CoreIntType": 0, "CoreStringType": 1, "CoreBytesType": 1,
                  "CoreDoubleType": 2, "CoreColorType": 3, "CoreBoolType": 4}.get(ct, ftype.get(k))
            name = props.get(k, (None, str(k)))[1]
            if ft == 0: v = vu()
            elif ft == 1:
                n = vu(); v = b[p:p+n]; p += n
                if o["_t"] != "FileAssetContents":
                    try: v = v.decode()
                    except Exception: v = f"<{n} bytes>"
            elif ft == 2: v = struct.unpack_from("<f", b, p)[0]; p += 4
            elif ft == 3: v = struct.unpack_from("<I", b, p)[0]; p += 4
            elif ft == 4: v = b[p] == 1; p += 1
            else:
                raise SystemExit(f"unknown property {k} {props.get(k)} at byte {p} in {o['_t']}")
            o[name] = v
        objs.append(o)
    return objs


if __name__ == "__main__":
    path = sys.argv[1]
    objs = load(path)
    if "--bodies" in sys.argv:
        out = sys.argv[sys.argv.index("--bodies") + 1]
        os.makedirs(out, exist_ok=True)
        last = None
        for o in objs:
            if o["_t"] == "ImageAsset": last = o.get("name")
            elif o["_t"] == "FileAssetContents" and last and "body" in last:
                open(os.path.join(out, last + ".png"), "wb").write(o["bytes"]); last = None
        print("bodies written to", out); raise SystemExit
    ab = next(i for i, o in enumerate(objs) if o["_t"] == "Artboard")
    st = next(i for i in range(ab, len(objs)) if objs[i]["_t"] in ("LinearAnimation", "StateMachine"))
    comps = objs[ab:st]
    assets = [o.get("name") for o in objs if o["_t"] == "ImageAsset"]
    fig = next(k for k, c in enumerate(comps) if c["_t"] == "Node" and c.get("parentId") == 0)
    lift = next(k for k, c in enumerate(comps) if c.get("parentId") == fig and c["_t"] == "Node")
    bob = next(k for k, c in enumerate(comps) if c.get("parentId") == lift and c["_t"] == "Node")
    print(f"figure #{fig} at ({comps[fig].get('x', 0)}, {comps[fig].get('y', 0)}), Lift #{lift}, Bob #{bob}")
    for k, c in enumerate(comps):
        if c["_t"] == "Image" and "body" in (assets[c.get("assetId", 0)] or ""):
            print(f"  body {assets[c.get('assetId', 0)]:<20} centre ({c.get('x', 0)}, {c.get('y', 0)})")
    cur = None
    for o in objs[st:]:
        t = o["_t"]
        if t == "LinearAnimation": cur = o.get("name"); ko = None
        elif t == "StateMachine": cur = None
        elif cur and t == "KeyedObject": ko = o.get("objectId", 0)
        elif cur and t == "KeyedProperty": kp = props.get(o.get("propertyKey", 0), (None, "?"))[1]
        elif cur and t.startswith("KeyFrame") and ko in (lift, bob):
            print(f"  {cur:>6} {'Lift' if ko == lift else 'Bob'}.{kp} frame {o.get('frame', 0)} = {o.get('value', 0)}")
