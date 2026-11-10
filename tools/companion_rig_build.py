"""Build the companions' Rive rig (one generic rig, re-skinned per creature).

    python3 tools/companion_rig_build.py build  <fileId> <creature> <cutDir>
    python3 tools/companion_rig_build.py swap   <fileId> <creature> <cutDir>
    python3 tools/companion_rig_build.py export <fileId> <outPath>

<cutDir>/<creature>/ holds body-1..7.png, chest-1..7.png and boxes.txt, made by
    swift tools/companion_cut.swift mockups/companions/master <creature> <cutDir>/<creature> 1.3
(images at 1.3x the 664x744 canvas, placed at 100/1.3 percent).

The rig mirrors Otto's aura rig (tools/otto_aura_rig_build.py), seven looks,
no bugs, no leaves:
  Artboard "Companion" 664x744, the only artboard. View model "Companion":
  stage (number, 0 until the app speaks), snap (boolean).
  Figure (332, 649) > Shadow, Lift > Bob > Back (GlowSize>Glow, Halo>Mandala,
  ring back arcs) / Stages (S1..S7: Body + Chest) / Front (ring front arcs, motes).
  Layers: Stage (Entry->Sk instant; Sj->Sk 500 ms, or instant when snap),
  Float (stage >= 6), Breath (chest patches, 10 s), Aura (9.6 s), Halo (12 s).
Rive traps honoured (CLAUDE.md): view model FIRST; group_editor ignores x/y;
groups/shapes land in front, images behind; uploaded images need 358=0,801=true;
image origin is a PERCENT; one artboard only or the export drops the rig.
"""
import sys, os, json, math, base64
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rivepy
from otto_aura_motion import MOTES

DENSITY = 1.3
IMG_SCALE = 100 / DENSITY
CHEST_OY = 85                  # chest patch scales from 85% down its box: low in the belly
T = 576                        # aura loop, frames
EASE = {"x1": 0.42, "y1": 0, "x2": 0.58, "y2": 1}
STATE = os.environ.get("COMPANION_STATE", "/private/tmp/claude-501/-Users-melvinvancleave-808/be09d0e3-7276-401b-bac8-f271c46fdece/scratchpad/rive/companion_state.json")
LIFT = {6: -26, 7: -40}
GLOW_OP = {1: 0, 2: 0, 3: 0, 4: 22, 5: 45, 6: 72, 7: 100}
GLOW_SC = {1: 60, 2: 60, 3: 60, 4: 72, 5: 86, 6: 100, 7: 116}

FILE_ID = None


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


def read_boxes(cut):
    boxes = {}
    for line in open(os.path.join(cut, "boxes.txt")):
        n, x, y, w, h = line.split()
        boxes[n] = tuple(float(v) for v in (x, y, w, h))
    return boxes


def body_place(box):
    x0, y0, w, h = box
    return {13: x0 + w / 2 - 332, 14: y0 + h / 2 - 649, 16: IMG_SCALE, 17: IMG_SCALE}


def chest_place(box, ox_key, oy_key):
    x0, y0, w, h = box
    return {ox_key: 50, oy_key: CHEST_OY, 13: x0 + w / 2 - 332, 14: y0 + h * CHEST_OY / 100 - 649, 16: IMG_SCALE, 17: IMG_SCALE}


def halo_place(boxes):
    # behind the head of the serene look: centre 27% down the stage-7 figure,
    # drawn at 80% (outer ring 320 across) so it stays inside the artboard
    x0, y0, w, h = boxes["figure-7"]
    return {13: 0, 14: y0 + h * 0.27 - 649, 16: 80, 17: 80}


def glow_place(boxes):
    x0, y0, w, h = boxes["figure-4"]
    return {13: 0, 14: y0 + h * 0.5 - 649}


def upload(creature, cut):
    assets = {}
    have = {a["name"] for a in call("assets_tool", {"command": "listAssets", "data": {"listAssets": {}}}).get("assets", [])}
    for kind in ("body", "chest"):
        for i in range(1, 8):
            name = "%s-%s-%d" % (creature, kind, i)
            if name in have:      # a rerun after a failure: reuse what is already up
                continue
            b64 = base64.b64encode(open(os.path.join(cut, "%s-%d.png" % (kind, i)), "rb").read()).decode()
            call("upload_asset", {"file": "data:image/png;name=%s.png;base64,%s" % (name, b64), "name": name})
    # Look ids up by name: an upload can hand back an id that never registers.
    listed = call("assets_tool", {"command": "listAssets", "data": {"listAssets": {}}})
    flat = []
    def walk(x):
        if isinstance(x, dict):
            if "id" in x and "name" in x:
                flat.append(x)
            for v in x.values():
                walk(v)
        elif isinstance(x, list):
            for v in x:
                walk(v)
    walk(listed)
    for kind in ("body", "chest"):
        for i in range(1, 8):
            name = "%s-%s-%d" % (creature, kind, i)
            hit = [a for a in flat if a["name"] in (name, name + ".png")]
            if not hit:
                sys.exit("asset %s did not register" % name)
            assets["%s-%d" % (kind, i)] = hit[-1]["id"]
    setp({a: {358: 0, 801: True} for a in assets.values()})
    return assets


def mandala_paths():
    paths, n = [], 12
    star = []
    for j in range(2 * n + 1):
        r = 138 if j % 2 == 0 else 112
        a = math.pi * j / n - math.pi / 2
        star.append(dict(commandType="moveTo" if j == 0 else "lineTo", x=r * math.cos(a), y=r * math.sin(a)))
    star.append(dict(commandType="close"))
    paths.append({"name": "star", "commands": star})
    petals = []
    for j in range(n):
        a = 2 * math.pi * (j + 0.5) / n - math.pi / 2
        c, s = math.cos(a), math.sin(a)
        def P(u, v):  # u along the ray, v across it
            return u * c - v * s, u * s + v * c
        p0, p1 = P(150, 0), P(186, 0)
        c1, c2, c3, c4 = P(160, 12), P(176, 12), P(176, -12), P(160, -12)
        petals.append({"name": "petal%d" % j, "commands": [
            dict(commandType="moveTo", x=p0[0], y=p0[1]),
            dict(commandType="cubicTo", control1X=c1[0], control1Y=c1[1], control2X=c2[0], control2Y=c2[1], endX=p1[0], endY=p1[1]),
            dict(commandType="cubicTo", control1X=c3[0], control1Y=c3[1], control2X=c4[0], control2Y=c4[1], endX=p0[0], endY=p0[1]),
            dict(commandType="close")]})
    return [{"name": "star", "commands": star}], petals


def arc(rx, ry, upper):
    k = 0.5523
    if not upper:
        return [dict(commandType="moveTo", x=rx, y=0),
                dict(commandType="cubicTo", control1X=rx, control1Y=k * ry, control2X=k * rx, control2Y=ry, endX=0, endY=ry),
                dict(commandType="cubicTo", control1X=-k * rx, control1Y=ry, control2X=-rx, control2Y=k * ry, endX=-rx, endY=0)]
    return [dict(commandType="moveTo", x=-rx, y=0),
            dict(commandType="cubicTo", control1X=-rx, control1Y=-k * ry, control2X=-k * rx, control2Y=-ry, endX=0, endY=-ry),
            dict(commandType="cubicTo", control1X=k * rx, control1Y=-ry, control2X=rx, control2Y=-k * ry, endX=rx, endY=0)]


def origin_keys(image_id):
    pk = call("query_property_keys", {"objectIds": [image_id]})
    s = json.dumps(pk)
    found = {}
    def walk(x):
        if isinstance(x, dict):
            for k, v in x.items():
                if isinstance(v, int) and k.lower().replace(" ", "") in ("originx", "originy"):
                    found[k.lower().replace(" ", "")] = v
                if isinstance(v, str) and k.lower() in ("name",) and v.lower().replace(" ", "") in ("originx", "originy"):
                    kk = x.get("key") or x.get("propertyKey")
                    if kk is not None:
                        found[v.lower().replace(" ", "")] = int(kk)
                walk(v)
        elif isinstance(x, list):
            for v in x:
                walk(v)
    walk(pk)
    if len(found) != 2:
        sys.exit("could not find originX/originY keys: " + s[:1500])
    return found["originx"], found["originy"]


def build(creature, cut):
    guard()
    ids = {"creature": creature}
    boxes = read_boxes(cut)
    boards = call("open_file_editor", {"command": "listArtboards", "data": {"listArtboards": {}}})["artboards"]
    if len(boards) > 1:
        sys.exit("expected at most one artboard, found %d" % len(boards))
    if not boards:
        boards = call("open_file_editor", {"command": "createArtboard", "data": {"createArtboard": [{"name": "Companion"}]}})["artboards"]
    board = boards[0]["id"]
    call("open_file_editor", {"command": "renameArtboard", "data": {"renameArtboard": [{"artboardId": board, "newName": "Companion"}]}})
    call("open_file_editor", {"command": "resizeArtboard", "data": {"resizeArtboard": [{"artboardId": board, "width": 664, "height": 744}]}})
    tree = call("get_artboard_hierarchy", {"depth": 2})["objects"]
    fills = [o["id"] for o in tree if "Fill" in o["types"]]
    if fills:
        call("delete_objects", {"objectIds": fills})
    ids["board"] = board
    print("artboard", board, flush=True)

    # 1. View model first. In this editor the data panel's listViewModels came
    # back EMPTY even for a view model that exists and exports (checked by
    # exporting and reading the names), so the proof is the export, not the
    # listing. COMPANION_VM="vm,stage,snap" reuses one already made.
    if os.environ.get("COMPANION_VM"):
        vm_id, sp, snp = os.environ["COMPANION_VM"].split(",")
        props = {"stage": sp, "snap": snp}
    else:
        vm = call("viewmodel_editor", {"command": "createViewModels", "data": {"createViewModels": {"viewModels": [
            {"name": "Companion", "viewModelProperties": [{"name": "stage", "propertyType": "number"},
                                                          {"name": "snap", "propertyType": "boolean"}]}]}}})["viewModels"][0]
        vm_id = vm["id"]
        props = {p["name"]: p["id"] for p in vm["viewModelProperties"]}
    call("viewmodel_editor", {"command": "bindViewModelToArtboard", "data": {"bindViewModelToArtboard": {"artboardId": board, "viewModelId": vm_id}}})
    ids.update(vm=vm_id, stageProp=props["stage"], snapProp=props["snap"])
    print("view model", vm_id, props, flush=True)

    # 2. Art.
    assets = upload(creature, cut)
    ids["assets"] = assets
    print("assets", len(assets), flush=True)

    # 3. Tree. Groups land in FRONT of siblings: back-most first.
    fig = group("Figure", board)
    setp({fig: {13: 332, 14: 649}})
    lift = group("Lift", fig)
    bob = group("Bob", lift)
    back, stages, front = group("Back", bob), group("Stages", bob), group("Front", bob)
    ids.update(Figure=fig, Lift=lift, Bob=bob, Back=back, Stages=stages, Front=front)
    for k in range(1, 8):
        ids["S%d" % k] = group("S%d" % k, stages)
    setp({g: {13: 0, 14: 0} for g in (lift, bob, back, stages, front)})
    setp({ids["S%d" % k]: {13: 0, 14: 0} for k in range(1, 8)})
    okeys = None
    for k in range(1, 8):
        sk = ids["S%d" % k]
        # images land BEHIND siblings: chest first, then the body behind it
        c = call("assets_tool", {"command": "addImageInstance", "data": {"addImageInstance": {"assetId": assets["chest-%d" % k], "parentId": sk, "name": "Chest%d" % k}}})["imageId"]
        b = call("assets_tool", {"command": "addImageInstance", "data": {"addImageInstance": {"assetId": assets["body-%d" % k], "parentId": sk, "name": "Body%d" % k}}})["imageId"]
        if okeys is None:
            okeys = origin_keys(c)
            print("origin keys", okeys, flush=True)
        setp({b: body_place(boxes["body-%d" % k]), c: chest_place(boxes["chest-%d" % k], *okeys)})
        ids["Chest%d" % k], ids["Body%d" % k] = c, b
    ids["originKeys"] = okeys
    json.dump(ids, open(STATE, "w"), indent=1)

    # 4. Light. Shapes land in FRONT: glow first, then halo over it.
    shapes = lambda specs: call("path_editor", {"command": "createParametricShapes", "data": {"createParametricShapes": {"shapes": specs}}})
    gsize = group("GlowSize", back)
    setp({gsize: glow_place(boxes)})
    shapes([{"primitive": "ellipse", "name": "Glow", "parentId": gsize, "x": 0, "y": 0, "width": 600, "height": 640,
             "paints": [{"paintType": "fill", "gradient": {"type": "radial", "stops": [
                 {"color": "#b3fff0bf", "position": 0}, {"color": "#59ffd27a", "position": 50}, {"color": "#00ffbd4d", "position": 100}]}}]}])
    ids["GlowSize"], ids["Glow"] = gsize, find("Glow")
    setp({ids["Glow"]: {13: 0, 14: 0}})
    halo = group("Halo", back)
    setp({halo: halo_place(boxes)})
    mand = group("Mandala", halo)
    ids["Halo"], ids["Mandala"] = halo, mand
    star, petals = mandala_paths()
    gold = {"paintType": "stroke", "color": "#e6ffe39a", "width": 2.4}
    soft = {"paintType": "stroke", "color": "#80fff2c8", "width": 7, "feather": {"strength": 8}}
    call("path_editor", {"command": "createShapes", "data": {"createShapes": {"shapes": [
        {"parentId": mand, "name": "HaloStar", "x": 0, "y": 0, "paints": [soft, gold], "paths": star},
        {"parentId": mand, "name": "HaloPetals", "x": 0, "y": 0,
         "paints": [{"paintType": "fill", "color": "#8cffe6a8"}, {"paintType": "stroke", "color": "#d9ffdc8a", "width": 1.4}], "paths": petals}]}}})
    shapes([{"primitive": "ellipse", "name": "HaloRingOuter", "parentId": mand, "x": 0, "y": 0, "width": 400, "height": 400, "paints": [soft, gold]},
            {"primitive": "ellipse", "name": "HaloRingInner", "parentId": mand, "x": 0, "y": 0, "width": 200, "height": 200,
             "paints": [{"paintType": "stroke", "color": "#b3fff4d2", "width": 1.6}]}])
    shapes([{"primitive": "ellipse", "name": "HaloDot%d" % j, "parentId": mand,
             "x": 162 * math.cos(2 * math.pi * j / 12 - math.pi / 2), "y": 162 * math.sin(2 * math.pi * j / 12 - math.pi / 2),
             "width": 9, "height": 9, "paints": [{"paintType": "fill", "color": "#f2fff3d0"}]} for j in range(12)])
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
            setp({ids[nm]: {13: 0, 14: cy, 15: tilt}})
            strokes = [o["id"] for o in call("query_objects", {"objectIds": [ids[nm]], "depth": 2})["objects"] if "Stroke" in o["types"]]
            trims[nm] = call("path_editor", {"command": "addTrimPaths", "data": {"addTrimPaths": {"paintIds": [strokes[-1]], "start": 0, "end": 0}}})["trimPaths"][0]["id"]
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
    json.dump(ids, open(STATE, "w"), indent=1)
    print("light done", flush=True)

    # 5. Timelines.
    anims = call("animation_editor", {"command": "listLinearAnimations", "data": {"listLinearAnimations": {}}})["linearAnimations"]
    specs = [{"name": "S%d" % k, "duration": 1 / 60} for k in range(1, 8)] + [
        {"name": "Still", "duration": 1 / 60}, {"name": "Float", "duration": 5.0}, {"name": "Breathe", "duration": 10.0},
        {"name": "Aura", "duration": 9.6}, {"name": "Halo", "duration": 12.0}]
    if anims:
        call("animation_editor", {"command": "renameAnimations", "data": {"renameAnimations": {"animations": [{"animationId": anims[0]["id"], "name": "S1"}]}}})
        specs = specs[1:]
    call("animation_editor", {"command": "createLinearAnimations", "data": {"createLinearAnimations": {"linearAnimations": specs}}})
    A = {a["name"]: a["id"] for a in call("animation_editor", {"command": "listLinearAnimations", "data": {"listLinearAnimations": {}}})["linearAnimations"]}
    # 57 = duration (frames), 59 = loop value (1 = loop)
    setp(dict([(A["S%d" % k], {57: 1}) for k in range(1, 8)] + [(A["Still"], {57: 1})] +
              [(A["Float"], {57: 300, 59: 1}), (A["Breathe"], {57: 600, 59: 1}), (A["Aura"], {57: T, 59: 1}), (A["Halo"], {57: 720, 59: 1})]))
    for k in range(1, 8):
        ks = [key(ids["S%d" % j], 18, 0, 100 if j == k else 0) for j in range(1, 8)]
        ks += [key(ids["Glow"], 18, 0, GLOW_OP[k]), key(ids["GlowSize"], 16, 0, GLOW_SC[k]), key(ids["GlowSize"], 17, 0, GLOW_SC[k])]
        for side in ("Back", "Front"):
            ks += [key(ids["Ring1" + side], 18, 0, 100 if k >= 6 else 0), key(ids["Ring2" + side], 18, 0, 100 if k >= 6 else 0)]
        ks += [key(ids["MotesA"], 18, 0, 100 if k >= 5 else 0), key(ids["MotesB"], 18, 0, 100 if k >= 6 else 0),
               key(ids["MotesC"], 18, 0, 100 if k == 7 else 0), key(ids["Halo"], 18, 0, 100 if k == 7 else 0),
               key(ids["Lift"], 14, 0, LIFT.get(k, 0))]
        keys(A["S%d" % k], ks)
    keys(A["Still"], [key(ids["Bob"], 14, 0, 0), key(ids["Shadow"], 18, 0, 0), key(ids["Shadow"], 16, 0, 100), key(ids["Shadow"], 17, 0, 100)])
    fl = []
    for f, y, op, sc in ((0, 0, 55, 100), (150, -10, 32, 86), (300, 0, 55, 100)):
        fl += [key(ids["Bob"], 14, f, y, "cubic"), key(ids["Shadow"], 18, f, op, "cubic"),
               key(ids["Shadow"], 16, f, sc, "cubic"), key(ids["Shadow"], 17, f, sc, "cubic")]
    keys(A["Float"], fl)
    br = []
    for n in range(1, 8):
        for f, sx, sy in ((0, 100, 100), (300, 110, 114), (600, 100, 100)):
            br += [key(ids["Chest%d" % n], 16, f, IMG_SCALE * sx / 100, "cubic"), key(ids["Chest%d" % n], 17, f, IMG_SCALE * sy / 100, "cubic")]
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
    keys(A["Aura"], au)
    keys(A["Halo"], [key(ids["Mandala"], 15, 0, 0), key(ids["Mandala"], 15, 720, 30)])
    ids["anims"] = A
    json.dump(ids, open(STATE, "w"), indent=1)
    print("timelines done", flush=True)

    # 6. The machine.
    sms = call("animation_editor", {"command": "listStateMachines", "data": {"listStateMachines": {}}})["stateMachines"]
    if not sms:
        call("animation_editor", {"command": "createStateMachine", "data": {"createStateMachine": {"name": "Companion"}}})
        sms = call("animation_editor", {"command": "listStateMachines", "data": {"listStateMachines": {}}})["stateMachines"]
    sm = sms[0]
    call("rename_objects", {"renames": [{"id": sm["id"], "name": "Companion"}, {"id": sm["layers"][0]["id"], "name": "Stage"}]})
    layer = sm["layers"][0]["id"]
    def qlayer():
        q = call("animation_editor", {"command": "queryStateMachineLayer", "data": {"queryStateMachineLayer": {"layerId": layer}}})
        return q.get("layer", q)
    q = qlayer()
    entry = q["entryStateId"]
    if q["transitions"]:
        call("delete_objects", {"objectIds": [t["id"] for t in q["transitions"]]})
    have = {s.get("name"): s["id"] for s in q["states"] if s.get("type") == "animation"}
    want = [{"name": "S%d" % k, "linearAnimationName": "S%d" % k, "x": 160 + 120 * (k - 1), "y": 140} for k in range(1, 8) if "S%d" % k not in have]
    stray = [sid for nm, sid in have.items() if nm not in ["S%d" % k for k in range(1, 8)]]
    if stray:
        call("delete_objects", {"objectIds": stray})
    if want:
        call("animation_editor", {"command": "createStates", "data": {"createStates": {"layerId": layer, "states": want}}})
    q = qlayer()
    st = {x["name"]: x["id"] for x in q["states"] if x.get("type") == "animation"}
    order = ["S%d" % k for k in range(1, 8)]
    # Each Sj->Sk twice: once faded (snap false), once instant (snap true).
    payload = [{"id": entry, "transitions": [{"to": st[n]} for n in order]}]
    payload += [{"id": st[a], "transitions": [{"to": st[b]} for b in order if b != a for _ in (0, 1)]} for a in order]
    call("animation_editor", {"command": "createTransitions", "data": {"createTransitions": {"states": payload}}})
    q = qlayer()
    byid = {v: k for k, v in st.items()}
    conds, durs, seen = [], {}, {}
    sp, snp = ids["stageProp"], ids["snapProp"]
    for t in q["transitions"]:
        to = byid[t["toStateId"]]
        c = [{"leftComparator": {"viewModelPropertyId": sp}, "comparationOperation": "equal",
              "rightComparator": {"valueType": "constantValueType", "value": int(to[1:])}}]
        if t["fromStateId"] == entry:
            durs[t["id"]] = {158: 0}
        else:
            pair = (t["fromStateId"], t["toStateId"])
            twin = seen.get(pair, 0)
            seen[pair] = twin + 1
            c.append({"leftComparator": {"viewModelPropertyId": snp}, "comparationOperation": "equal",
                      "rightComparator": {"valueType": "constantValueType", "value": twin == 1}})
            durs[t["id"]] = {158: 0 if twin == 1 else 500}
        conds.append({"id": t["id"], "conditions": c})
    if any(v != 2 for v in seen.values()) or len(seen) != 42:
        sys.exit("expected 42 pairs of twins, got %d pairs %s" % (len(seen), set(seen.values())))
    for i in range(0, len(conds), 40):
        call("animation_editor", {"command": "createConditions", "data": {"createConditions": {"transitions": conds[i:i + 40]}}})
    setp(durs)
    call("animation_editor", {"command": "createStateMachineLayers", "data": {"createStateMachineLayers": {"stateMachineId": sm["id"], "layers": [
        {"name": "Float", "states": [{"name": "Still", "linearAnimationName": "Still", "x": 160, "y": 0}, {"name": "Float", "linearAnimationName": "Float", "x": 320, "y": 0}],
         "otherTransitions": [{"from": "{Entry State}", "to": "Still"}, {"from": "Still", "to": "Float"}, {"from": "Float", "to": "Still"}]},
        {"name": "Breath", "states": [{"name": "Breathe", "linearAnimationName": "Breathe", "x": 160, "y": 0}], "otherTransitions": [{"from": "{Entry State}", "to": "Breathe"}]},
        {"name": "Aura", "states": [{"name": "Aura", "linearAnimationName": "Aura", "x": 160, "y": 0}], "otherTransitions": [{"from": "{Entry State}", "to": "Aura"}]},
        {"name": "Halo", "states": [{"name": "Halo", "linearAnimationName": "Halo", "x": 160, "y": 0}], "otherTransitions": [{"from": "{Entry State}", "to": "Halo"}]}]}}})
    q = call("animation_editor", {"command": "queryStateMachine", "data": {"queryStateMachine": {"stateMachineId": sm["id"]}}})
    fl = [l for l in q["layers"] if l["layerName"] == "Float"][0]
    names = {x["id"]: (x.get("name") or x["type"]) for x in fl["states"]}
    tr = {(names[t["fromStateId"]], names[t["toStateId"]]): t["id"] for t in fl["transitions"]}
    call("animation_editor", {"command": "createConditions", "data": {"createConditions": {"transitions": [
        {"id": tr[("Still", "Float")], "conditions": [{"leftComparator": {"viewModelPropertyId": sp}, "comparationOperation": "greaterThanOrEqual", "rightComparator": {"valueType": "constantValueType", "value": 6}}]},
        {"id": tr[("Float", "Still")], "conditions": [{"leftComparator": {"viewModelPropertyId": sp}, "comparationOperation": "lessThan", "rightComparator": {"valueType": "constantValueType", "value": 6}}]}]}}})
    setp({tr[("Still", "Float")]: {158: 700}, tr[("Float", "Still")]: {158: 700}})
    ids["sm"] = sm["id"]
    base_look(ids)
    json.dump(ids, open(STATE, "w"), indent=1)
    print("built", flush=True)


def base_look(ids, k=4):
    """Design-time look: stage k's light. The app's stage 0 waits at Entry on this."""
    base = {ids["S%d" % j]: {18: 100 if j == k else 0} for j in range(1, 8)}
    base[ids["Glow"]] = {18: GLOW_OP[k]}
    base[ids["GlowSize"]] = {16: GLOW_SC[k], 17: GLOW_SC[k]}
    for n in ("Ring1Back", "Ring1Front", "Ring2Back", "Ring2Front"):
        base[ids[n]] = {18: 100 if k >= 6 else 0}
    base[ids["MotesA"]] = {18: 100 if k >= 5 else 0}
    base[ids["MotesB"]] = {18: 100 if k >= 6 else 0}
    base[ids["MotesC"]] = {18: 100 if k == 7 else 0}
    base[ids["Halo"]] = {18: 100 if k == 7 else 0}
    base[ids["Shadow"]] = {18: 0}
    base[ids["Lift"]] = {14: LIFT.get(k, 0)}
    setp(base)


def swap(creature, cut):
    ids = json.load(open(STATE))
    old = dict(ids["assets"])
    boxes = read_boxes(cut)
    assets = upload(creature, cut)
    okx, oky = ids["originKeys"]
    # point each image at its new asset (property 'assetId' on Image), then re-place
    pk = call("query_property_keys", {"objectIds": [ids["Body1"]]})
    akey = ids.get("assetKey")
    if akey is None:
        def walk(x):
            if isinstance(x, dict):
                for kk, v in x.items():
                    if isinstance(v, int) and kk.lower() == "assetid":
                        return v
                    if isinstance(v, str) and v.lower() == "assetid" and isinstance(x.get("key"), int):
                        return x["key"]
                    r = walk(v)
                    if r is not None:
                        return r
            elif isinstance(x, list):
                for v in x:
                    r = walk(v)
                    if r is not None:
                        return r
        akey = walk(pk)
        if akey is None:
            sys.exit("no assetId key: " + json.dumps(pk)[:1500])
    vals = {}
    for k in range(1, 8):
        vals[ids["Body%d" % k]] = {**body_place(boxes["body-%d" % k]), akey: assets["body-%d" % k]}
        vals[ids["Chest%d" % k]] = {**chest_place(boxes["chest-%d" % k], okx, oky), akey: assets["chest-%d" % k]}
    vals[ids["Halo"]] = halo_place(boxes)
    vals[ids["GlowSize"]] = {**glow_place(boxes), 16: GLOW_SC[4], 17: GLOW_SC[4]}
    setp(vals)
    call("delete_objects", {"objectIds": list(old.values())})
    ids["assets"], ids["creature"], ids["assetKey"] = assets, creature, akey
    json.dump(ids, open(STATE, "w"), indent=1)
    print("swapped to", creature, flush=True)


if __name__ == "__main__":
    cmd, FILE_ID = sys.argv[1], int(sys.argv[2])
    if cmd == "build":
        build(sys.argv[3], os.path.join(sys.argv[4], sys.argv[3]))
    elif cmd == "swap":
        swap(sys.argv[3], os.path.join(sys.argv[4], sys.argv[3]))
    elif cmd == "place":
        ids = json.load(open(STATE)); boxes = read_boxes(os.path.join(sys.argv[4], sys.argv[3]))
        setp({ids["Halo"]: halo_place(boxes), ids["GlowSize"]: glow_place(boxes)})
    elif cmd == "look":
        base_look(json.load(open(STATE)), int(sys.argv[3]))
    else:
        sys.exit("unknown command " + cmd)
