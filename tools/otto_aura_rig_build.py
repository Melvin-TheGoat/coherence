"""Build Otto's aura rig from scratch in a BLANK Rive file that is open in front.

Every lesson from the first build is in here:
  - the view model is made FIRST (deleting a view model broke a file's data
    panel: new ones were never listed and never exported)
  - group_editor ignores x/y, and a group made under a moved parent is
    offset to cancel it: positions are written after, and Lift is zeroed
  - new GROUPS and SHAPES land IN FRONT of their siblings, new IMAGES land
    BEHIND them; the creation order below relies on both
  - uploaded images default to hosted and not exported: 358 = 0, 801 = true
Run: python3 tools/otto_aura_rig_build.py <fileId-of-the-blank-file>
from a working folder holding rig/crop/*.png, rig/crop/boxes.txt and
aura7/fly/island-1.png (see tools/otto_aura_cut.swift and the CLAUDE.md
section "OTTO'S AURA RIG IN RIVE"). The second pass, done by hand calls on
2026-09-23 and recorded there, swapped in the clean bodies (the sheet with
no bugs or light), replaced the fly, and added the moth, the beetle and the
mandala with their keys and the Halo layer.
"""
import sys, os, json, math, base64, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rivepy
from otto_aura_motion import MOTES, fly_keys

HERE = os.path.dirname(os.path.abspath(__file__))
FILE_ID = int(sys.argv[1])
T = 576          # the aura loop, frames (9.6 s at 60 fps)
EASE = {"x1": 0.42, "y1": 0, "x2": 0.58, "y2": 1}


def guard():
    info = rivepy.call("session_info", {})
    if info.get("activeFileId") != FILE_ID:
        sys.exit("ABORT: the file in front is %s (%s), not %s" % (info.get("activeFileName"), info.get("activeFileId"), FILE_ID))


def call(tool, args):
    guard()
    r = rivepy.call(tool, args)
    if isinstance(r, dict) and r.get("success") is False:
        sys.exit("%s failed: %s" % (tool, json.dumps(r)[:800]))
    return r


def setp(values):
    call("set_property_values", {"propertyValues": {k: {str(p): v for p, v in d.items()} for k, d in values.items()}})


def key(obj, prop, frame, val, interp="linear"):
    d = {"objectId": obj, "propertyKey": prop, "frame": int(round(frame)), "value": val if isinstance(val, bool) else round(val, 3),
         "interpolationType": interp}
    if interp == "cubic":
        d["cubicParams"] = EASE
    return d


def keys(anim, ks):
    for i in range(0, len(ks), 150):
        call("animation_editor", {"command": "modifyKeyFrames", "data": {"modifyKeyFrames": {"animationId": anim, "add": ks[i:i + 150]}}})


def find(name):
    objs = [o for o in call("find_objects", {"name": name})["objects"] if o["name"] == name]
    return objs[0]["id"]


def group(name, parent):
    g = call("group_editor", {"name": name, "parentId": parent})["group"]["id"]
    setp({g: {13: 0, 14: 0}})
    return g


def image(asset, parent, name, box):
    iid = call("assets_tool", {"command": "addImageInstance", "data": {"addImageInstance": {"assetId": asset, "parentId": parent, "name": name}}})["imageId"]
    x0, y0, w, h = box
    setp({iid: {13: x0 + w / 2 - 332, 14: y0 + h / 2 - 649}})
    return iid


def arc(rx, ry, upper):
    k = 0.5523
    if not upper:
        return [dict(commandType="moveTo", x=rx, y=0),
                dict(commandType="cubicTo", control1X=rx, control1Y=k * ry, control2X=k * rx, control2Y=ry, endX=0, endY=ry),
                dict(commandType="cubicTo", control1X=-k * rx, control1Y=ry, control2X=-rx, control2Y=k * ry, endX=-rx, endY=0)]
    return [dict(commandType="moveTo", x=-rx, y=0),
            dict(commandType="cubicTo", control1X=-rx, control1Y=-k * ry, control2X=-k * rx, control2Y=-ry, endX=0, endY=-ry),
            dict(commandType="cubicTo", control1X=k * rx, control1Y=-ry, control2X=rx, control2Y=-k * ry, endX=rx, endY=0)]


def leaf(h=24, w=10):
    return [dict(commandType="moveTo", x=0, y=-h),
            dict(commandType="cubicTo", control1X=w * 1.3, control1Y=-h * 0.45, control2X=w * 1.1, control2Y=h * 0.55, endX=0, endY=h),
            dict(commandType="cubicTo", control1X=-w * 1.1, control1Y=h * 0.55, control2X=-w * 1.3, control2Y=-h * 0.45, endX=0, endY=-h),
            dict(commandType="close")]


def main():
    guard()
    ids = {}
    boards = call("open_file_editor", {"command": "listArtboards", "data": {"listArtboards": {}}})["artboards"]
    if len(boards) > 1:
        sys.exit("expected at most one artboard in a blank file, found %d" % len(boards))
    if not boards:
        boards = call("open_file_editor", {"command": "createArtboard", "data": {"createArtboard": [{"name": "OttoAura"}]}})["artboards"]
    board = boards[0]["id"]
    call("open_file_editor", {"command": "renameArtboard", "data": {"renameArtboard": [{"artboardId": board, "newName": "OttoAura"}]}})
    print("artboard", board, flush=True)
    call("open_file_editor", {"command": "resizeArtboard", "data": {"resizeArtboard": [{"artboardId": board, "width": 664, "height": 744}]}})
    tree = call("get_artboard_hierarchy", {"depth": 2})["objects"]
    fills = [o["id"] for o in tree if "Fill" in o["types"]]
    if fills:
        call("delete_objects", {"objectIds": fills})

    # 1. The view model, first of anything.
    vm = call("viewmodel_editor", {"command": "createViewModels", "data": {"createViewModels": {"viewModels": [
        {"name": "OttoAura", "viewModelProperties": [{"name": "stage", "propertyType": "number"}]}]}}})["viewModels"][0]
    vm_id, stage_prop = vm["id"], vm["viewModelProperties"][0]["id"]
    listed = call("viewmodel_editor", {"command": "listViewModels", "data": {"listViewModels": {}}})["viewModels"]
    if not any(v["id"] == vm_id for v in listed):
        sys.exit("the new view model is not listed: this file's data panel is broken too")
    call("viewmodel_editor", {"command": "bindViewModelToArtboard", "data": {"bindViewModelToArtboard": {"artboardId": board, "viewModelId": vm_id}}})
    ids["vm"], ids["stageProp"] = vm_id, stage_prop

    print('art', flush=True)
    # 2. Art.
    boxes = {}
    for line in open(os.path.join(HERE, "rig/crop/boxes.txt")):
        n, x, y, w, h = line.split()
        boxes[n] = tuple(int(v) for v in (x, y, w, h))
    assets = {}
    files = [("body-%d" % i, "rig/crop/body-%d.png" % i) for i in range(1, 8)] + \
            [("chest-%d" % i, "rig/crop/chest-%d.png" % i) for i in range(1, 8)] + [("fly", "aura7/fly/island-1.png")]
    for name, path in files:
        b64 = base64.b64encode(open(os.path.join(HERE, path), "rb").read()).decode()
        assets[name] = call("upload_asset", {"file": "data:image/png;name=otto-aura-%s.png;base64,%s" % (name, b64),
                                             "name": "otto-aura-" + name})["asset"]["id"]
    setp({a: {358: 0, 801: True} for a in assets.values()})

    print('tree', flush=True)
    # 3. Tree. Groups land in FRONT of siblings, so back-most first.
    fig = group("Figure", board)
    setp({fig: {13: 332, 14: 649}})
    lift = group("Lift", fig)
    bob = group("Bob", lift)
    back, stages, bugs, front = group("Back", bob), group("Stages", bob), group("Bugs", bob), group("Front", bob)
    ids.update(Figure=fig, Lift=lift, Bob=bob, Back=back, Stages=stages, Bugs=bugs, Front=front)
    for k in range(1, 8):
        sk = group("S%d" % k, stages)
        ids["S%d" % k] = sk
        # Images land BEHIND siblings: chest first, then the body behind it.
        ids["Chest%d" % k] = image(assets["chest-%d" % k], sk, "Chest%d" % k, boxes["chest-%d" % k])
        ids["Body%d" % k] = image(assets["body-%d" % k], sk, "Body%d" % k, boxes["body-%d" % k])
    setp({g: {13: 0, 14: 0} for g in (lift, bob, back, stages, bugs, front)})

    print('light', flush=True)
    # 4. Light. Shapes land in FRONT: the glow first, then what goes over it.
    shapes = lambda specs: call("path_editor", {"command": "createParametricShapes", "data": {"createParametricShapes": {"shapes": specs}}})
    shapes([{"primitive": "ellipse", "name": "Glow", "parentId": back, "x": 0, "y": -300, "width": 600, "height": 640,
             "paints": [{"paintType": "fill", "gradient": {"type": "radial", "stops": [
                 {"color": "#b3fff0bf", "position": 0}, {"color": "#59ffd27a", "position": 50}, {"color": "#00ffbd4d", "position": 100}]}}]}])
    ids["Glow"] = find("Glow")
    # Leaves swirl BEHIND him: in front, one crossed his face.
    leaves = group("Leaves", back)
    ids["Leaves"] = leaves
    call("path_editor", {"command": "createShapes", "data": {"createShapes": {"shapes": [
        {"parentId": leaves, "name": "Leaf%d" % i, "x": 0, "y": -300,
         "paints": [{"paintType": "fill", "gradient": {"type": "linear", "stops": [{"color": "#ffb5d98a", "position": 0}, {"color": "#ff6fa653", "position": 100}]}},
                    {"paintType": "stroke", "color": "#99507f3c", "width": 1.2}],
         "paths": [{"name": "blade", "commands": leaf()},
                   {"name": "rib", "commands": [dict(commandType="moveTo", x=0, y=-20), dict(commandType="lineTo", x=0, y=20)]}]}
        for i in range(6)]}}})
    for i in range(6):
        ids["Leaf%d" % i] = find("Leaf%d" % i)
    faint = {"paintType": "stroke", "color": "#8cffe6a0", "width": 1.8}
    bright = {"paintType": "stroke", "color": "#fffff4cc", "width": 5.5, "feather": {"strength": 6}}
    trims = {}
    for name, rx, ry, cy, tilt in (("Ring1", 270, 60, -175, -7), ("Ring2", 240, 52, -95, 9)):
        for side, parent, upper in (("Back", back, True), ("Front", front, False)):
            nm = name + side
            call("path_editor", {"command": "createShapes", "data": {"createShapes": {"shapes": [
                {"parentId": parent, "name": nm, "x": 0, "y": cy, "paints": [faint, bright],
                 "paths": [{"name": "arc", "commands": arc(rx, ry, upper)}]}]}}})
            ids[nm] = find(nm)
            setp({ids[nm]: {15: tilt}})
            strokes = [o["id"] for o in call("query_objects", {"objectIds": [ids[nm]], "depth": 2})["objects"] if "Stroke" in o["types"]]
            t = call("path_editor", {"command": "addTrimPaths", "data": {"addTrimPaths": {"paintIds": [strokes[-1]], "start": 0, "end": 0}}})["trimPaths"][0]["id"]
            trims[nm] = t
    ids["trims"] = trims
    mote_paint = [{"paintType": "fill", "gradient": {"type": "radial", "stops": [
        {"color": "#ffffffff", "position": 0}, {"color": "#ffffeaa8", "position": 35}, {"color": "#00ffcf70", "position": 100}]}}]
    for setname, pts in MOTES.items():
        g = group("Motes" + setname, front)
        ids["Motes" + setname] = g
        shapes([{"primitive": "ellipse", "name": "Mote%s%d" % (setname, i), "parentId": g, "x": x, "y": y,
                 "width": 18, "height": 18, "paints": mote_paint} for i, (x, y) in enumerate(pts)])
        for i in range(len(pts)):
            ids["Mote%s%d" % (setname, i)] = find("Mote%s%d" % (setname, i))
    shapes([{"primitive": "ellipse", "name": "Shadow", "parentId": fig, "x": 0, "y": -2, "width": 330, "height": 46,
             "paints": [{"paintType": "fill", "gradient": {"type": "radial", "stops": [
                 {"color": "#47000000", "position": 0}, {"color": "#00000000", "position": 100}]}}]}])
    ids["Shadow"] = find("Shadow")
    call("reorder_objects", {"operations": [{"objectId": ids["Shadow"], "order": "sendToBack"}]})
    fly = call("assets_tool", {"command": "addImageInstance", "data": {"addImageInstance": {"assetId": assets["fly"], "parentId": bugs, "name": "Fly"}}})["imageId"]
    setp({fly: {13: 400, 14: -560, 16: 150, 17: 150}})
    ids["Fly"] = fly

    print('timelines', flush=True)
    # 5. Timelines.
    anims = call("animation_editor", {"command": "listLinearAnimations", "data": {"listLinearAnimations": {}}})["linearAnimations"]
    call("animation_editor", {"command": "renameAnimations", "data": {"renameAnimations": {"animations": [{"animationId": anims[0]["id"], "name": "S1"}]}}})
    specs = [{"name": "S%d" % k, "duration": 1 / 60} for k in range(2, 8)] + [
        {"name": "Still", "duration": 1 / 60}, {"name": "Float", "duration": 5.0}, {"name": "Breathe", "duration": 10.0},
        {"name": "Aura", "duration": 9.6}, {"name": "Bugs", "duration": 11.0}]
    call("animation_editor", {"command": "createLinearAnimations", "data": {"createLinearAnimations": {"linearAnimations": specs}}})
    A = {a["name"]: a["id"] for a in call("animation_editor", {"command": "listLinearAnimations", "data": {"listLinearAnimations": {}}})["linearAnimations"]}
    setp(dict([(A["S1"], {57: 1, 59: 0})] + [(A[n], {59: 1}) for n in ("Float", "Breathe", "Aura", "Bugs")]))
    glow = {1: 0, 2: 0, 3: 0, 4: 0, 5: 38, 6: 70, 7: 100}
    for k in range(1, 8):
        ks = [key(ids["S%d" % j], 18, 0, 100 if j == k else 0) for j in range(1, 8)]
        ks += [key(ids["Glow"], 18, 0, glow[k])]
        for side in ("Back", "Front"):
            ks += [key(ids["Ring1" + side], 18, 0, 100 if k >= 6 else 0), key(ids["Ring2" + side], 18, 0, 100 if k == 7 else 0)]
        ks += [key(ids["MotesA"], 18, 0, 100 if k >= 5 else 0), key(ids["MotesB"], 18, 0, 100 if k >= 6 else 0),
               key(ids["MotesC"], 18, 0, 100 if k == 7 else 0), key(ids["Leaves"], 18, 0, 100 if k == 7 else 0),
               key(ids["Bugs"], 18, 0, 100 if k <= 2 else 0), key(ids["Fly"], 18, 0, 100 if k == 1 else 0),
               key(ids["Lift"], 14, 0, {6: -26, 7: -40}.get(k, 0))]
        keys(A["S%d" % k], ks)
    keys(A["Still"], [key(ids["Bob"], 14, 0, 0), key(ids["Shadow"], 18, 0, 0), key(ids["Shadow"], 16, 0, 100), key(ids["Shadow"], 17, 0, 100)])
    fl = []
    for f, y, op, sc in ((0, 0, 55, 100), (150, -10, 32, 86), (300, 0, 55, 100)):
        fl += [key(ids["Bob"], 14, f, y, "cubic"), key(ids["Shadow"], 18, f, op, "cubic"),
               key(ids["Shadow"], 16, f, sc, "cubic"), key(ids["Shadow"], 17, f, sc, "cubic")]
    keys(A["Float"], fl)
    br = []
    for n in range(1, 8):
        x0, y0, w, h = boxes["chest-%d" % n]
        base = y0 + h / 2 - 649
        for f, sx, sy, dy in ((0, 100, 100, 0), (300, 108, 111, -3), (600, 100, 100, 0)):
            br += [key(ids["Chest%d" % n], 16, f, sx, "cubic"), key(ids["Chest%d" % n], 17, f, sy, "cubic"), key(ids["Chest%d" % n], 14, f, base + dy, "cubic")]
    keys(A["Breathe"], br)
    au = []
    for f, sc in ((0, 96), (144, 106), (288, 96), (432, 106), (576, 96)):
        au += [key(ids["Glow"], 16, f, sc, "cubic"), key(ids["Glow"], 17, f, sc, "cubic")]
    L = 35.0
    def comet(trim, period, offset):
        half = period / 2
        frames = {0, T}
        for c in range(-1, T // period + 2):
            for h in (0, L, 100, 100 + L):
                f = c * period + offset + h / 100 * half
                if 0 <= f <= T:
                    frames.add(round(f))
        out = []
        for f in sorted(frames):
            head = ((f - offset) % period) / half * 100
            st, en = (100.0, 100.0) if head - L >= 100 else (min(100, max(0, head - L)), min(100, max(0, head)))
            out += [key(trim, 114, f, st), key(trim, 115, f, en)]
        return out
    au += comet(trims["Ring1Front"], 192, 0) + comet(trims["Ring1Back"], 192, 96)
    au += comet(trims["Ring2Front"], 288, 0) + comet(trims["Ring2Back"], 288, 144)
    i = 0
    for setname, pts in MOTES.items():
        for j, (x, y) in enumerate(pts):
            oid = ids["Mote%s%d" % (setname, j)]
            t0 = ((i * 0.83) % 7.0) * 60
            life = 156
            au += [key(oid, 18, 0, 0), key(oid, 14, 0, y)]
            if t0 > 1:
                au += [key(oid, 18, t0, 0), key(oid, 14, t0, y)]
            au += [key(oid, 18, t0 + life * 0.45, 100, "cubic"), key(oid, 14, t0 + life * 0.45, y - 10),
                   key(oid, 18, t0 + life, 0), key(oid, 14, t0 + life, y - 22), key(oid, 18, T, 0), key(oid, 14, T, y)]
            i += 1
    for n in range(6):
        oid = ids["Leaf%d" % n]
        for f in range(0, T + 1, 24):
            u = ((f / T) - n / 6) % 1.0
            if u < 0.85:
                p = u / 0.85
                ang = 2 * math.pi * (p * 1.25 + n / 6)
                env = min(1, p / 0.12) * min(1, (1 - p) / 0.18)
                op = env * (60 + 40 * math.sin(ang))
                x, y = 300 * math.cos(ang), -70 - 520 * p + 45 * math.sin(ang)
                sc, rot = 82 + 18 * math.sin(ang), p * 540 + n * 60
            else:
                p = (u - 0.85) / 0.15
                ang = 2 * math.pi * (1.25 + n / 6) * (1 - p) + 2 * math.pi * (n / 6) * p
                op, x, y, sc, rot = 0, 300 * math.cos(ang), -590 + 520 * p, 80, 540 * (1 - p) + n * 60
            au += [key(oid, 13, f, x), key(oid, 14, f, y), key(oid, 15, f, rot), key(oid, 16, f, sc), key(oid, 17, f, sc), key(oid, 18, f, op)]
    keys(A["Aura"], au)
    random.seed(3)
    bg, seen = [], set()
    for t, x, y, op in fly_keys():
        f = int(round(t * 60))
        if f in seen:
            f += 1
        seen.add(f)
        cp = {"x1": 0.3, "y1": 0, "x2": 0.7, "y2": 1}
        bg += [dict(key(fly, 13, f, x, "cubic"), cubicParams=cp), dict(key(fly, 14, f, y, "cubic"), cubicParams=cp),
               key(fly, 18, f, op, "hold"), key(fly, 15, f, random.uniform(-25, 25))]
    keys(A["Bugs"], bg)
    ids["anims"] = A

    print('machine', flush=True)
    # 6. The machine.
    sm = call("animation_editor", {"command": "listStateMachines", "data": {"listStateMachines": {}}})["stateMachines"][0]
    call("rename_objects", {"renames": [{"id": sm["id"], "name": "OttoAura"}, {"id": sm["layers"][0]["id"], "name": "Stage"}]})
    layer = sm["layers"][0]["id"]
    q = call("animation_editor", {"command": "queryStateMachineLayer", "data": {"queryStateMachineLayer": {"layerId": layer}}})
    q = q.get("layer", q)
    entry = q["entryStateId"]
    if q["transitions"]:
        call("delete_objects", {"objectIds": [t["id"] for t in q["transitions"]]})
    s1 = [st for st in q["states"] if st.get("type") == "animation"][0]["id"]
    call("animation_editor", {"command": "createStates", "data": {"createStates": {"layerId": layer, "states": [
        {"name": "S%d" % k, "linearAnimationName": "S%d" % k, "x": 160 + 120 * (k - 1), "y": 140} for k in range(2, 8)]}}})
    q = call("animation_editor", {"command": "queryStateMachineLayer", "data": {"queryStateMachineLayer": {"layerId": layer}}})
    q = q.get("layer", q)
    st = {x["name"]: x["id"] for x in q["states"] if x.get("type") == "animation"}
    st["S1"] = s1
    order = ["S%d" % k for k in range(1, 8)]
    payload = [{"id": entry, "transitions": [{"to": st[n]} for n in order]}]
    payload += [{"id": st[a], "transitions": [{"to": st[b]} for b in order if b != a]} for a in order]
    call("animation_editor", {"command": "createTransitions", "data": {"createTransitions": {"states": payload}}})
    q = call("animation_editor", {"command": "queryStateMachineLayer", "data": {"queryStateMachineLayer": {"layerId": layer}}})
    q = q.get("layer", q)
    byid = {v: k for k, v in st.items()}
    conds, durs = [], {}
    for t in q["transitions"]:
        to = byid[t["toStateId"]]
        conds.append({"id": t["id"], "conditions": [{"leftComparator": {"viewModelPropertyId": stage_prop}, "comparationOperation": "equal",
                                                     "rightComparator": {"valueType": "constantValueType", "value": int(to[1:])}}]})
        durs[t["id"]] = {158: 0 if t["fromStateId"] == entry else 500}
    call("animation_editor", {"command": "createConditions", "data": {"createConditions": {"transitions": conds}}})
    setp(durs)
    call("animation_editor", {"command": "createStateMachineLayers", "data": {"createStateMachineLayers": {"stateMachineId": sm["id"], "layers": [
        {"name": "Float", "states": [{"name": "Still", "linearAnimationName": "Still", "x": 160, "y": 0}, {"name": "Float", "linearAnimationName": "Float", "x": 320, "y": 0}],
         "otherTransitions": [{"from": "{Entry State}", "to": "Still"}, {"from": "Still", "to": "Float"}, {"from": "Float", "to": "Still"}]},
        {"name": "Breath", "states": [{"name": "Breathe", "linearAnimationName": "Breathe", "x": 160, "y": 0}], "otherTransitions": [{"from": "{Entry State}", "to": "Breathe"}]},
        {"name": "Aura", "states": [{"name": "Aura", "linearAnimationName": "Aura", "x": 160, "y": 0}], "otherTransitions": [{"from": "{Entry State}", "to": "Aura"}]},
        {"name": "Bugs", "states": [{"name": "Bugs", "linearAnimationName": "Bugs", "x": 160, "y": 0}], "otherTransitions": [{"from": "{Entry State}", "to": "Bugs"}]}]}}})
    q = call("animation_editor", {"command": "queryStateMachine", "data": {"queryStateMachine": {"stateMachineId": sm["id"]}}})
    fl = [l for l in q["layers"] if l["layerName"] == "Float"][0]
    names = {x["id"]: (x.get("name") or x["type"]) for x in fl["states"]}
    tr = {(names[t["fromStateId"]], names[t["toStateId"]]): t["id"] for t in fl["transitions"]}
    call("animation_editor", {"command": "createConditions", "data": {"createConditions": {"transitions": [
        {"id": tr[("Still", "Float")], "conditions": [{"leftComparator": {"viewModelPropertyId": stage_prop}, "comparationOperation": "greaterThanOrEqual", "rightComparator": {"valueType": "constantValueType", "value": 6}}]},
        {"id": tr[("Float", "Still")], "conditions": [{"leftComparator": {"viewModelPropertyId": stage_prop}, "comparationOperation": "lessThan", "rightComparator": {"valueType": "constantValueType", "value": 6}}]}]}}})
    setp({tr[("Still", "Float")]: {158: 700}, tr[("Float", "Still")]: {158: 700}})
    ids["sm"] = sm["id"]

    print('base', flush=True)
    # 7. The look before the app says anything: Steady, no light, stage 0.
    base = {ids["S%d" % k]: {18: 100 if k == 4 else 0} for k in range(1, 8)}
    for n in ("Glow", "Ring1Back", "Ring1Front", "Ring2Back", "Ring2Front", "MotesA", "MotesB", "MotesC", "Leaves", "Bugs", "Shadow"):
        base[ids[n]] = {18: 0}
    base[ids["Lift"]] = {14: 0}
    setp(base)
    inst = call("viewmodel_editor", {"command": "listViewModelInstances", "data": {"listViewModelInstances": {"viewModelId": vm_id}}})["instances"]
    for ins in inst:
        for p in ins["viewModelProperties"]:
            setp({p["id"]: {575: 0}})
    json.dump(ids, open(os.path.join(HERE, "rig_state_v2.json"), "w"), indent=1)
    print("built; view model %s, stage %s, %d instances" % (vm_id, stage_prop, len(inst)))


if __name__ == "__main__":
    main()
