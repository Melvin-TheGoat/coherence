#!/usr/bin/env python3
"""Build Otto's seven-state aura rig in the open Rive file, and export it.

    python3 tools/otto_aura_rig.py build  <bodies-dir>   # from scratch, in an EMPTY file called OttoAura
    python3 tools/otto_aura_rig.py swap   <bodies-dir>   # new art for the seven bodies, rig untouched
    python3 tools/otto_aura_rig.py export                # write Coherence/Otto/OttoAura.riv, verified

`<bodies-dir>` holds body-1.png ... body-7.png, each the 664 x 744 canvas cut
by tools/otto_aura_cut.swift (--normalize 490), so all seven overlay exactly:
his body's bottom centre sits at (332, 649) in every one.

WHAT THE RIG DOES (Melvin, 2026-09-22: "the bugs should come and go
periodically. The aura should swirl around. He should be floating up and
down a little bit when hes floating. Use rive obviously"):

  - one view model property, `stage` (1-7); the app writes it and nothing else
  - a Stage layer: seven one-frame poses S1..S7 that say which body shows and
    which effects are on, cross-fading when the stage changes
  - a Float layer: from stage 6 he is lifted and bobs on a slow breath, with a
    soft shadow under him that shrinks as he rises
  - an Aura layer (always running, shown per stage): motes that twinkle and
    drift, a glow that pulses, rings of light that swirl round his middle,
    leaves that spiral up round him, a mandala that turns behind his head
  - a Bugs layer (always running, shown at stages 1-2): the fly buzzes in,
    circles his head and leaves; moth and beetle when their sprites exist

WHY IT IS ITS OWN FILE: the Otto.riv export only ever carried its FIRST
artboard (CLAUDE.md, "THE RIVE EXPORT ONLY EVER EMITTED THE FIRST
ARTBOARD"). So this rig lives in a file of its own with exactly one
artboard, and the session rig is never touched.

REQUIRES the Rive desktop editor with the OttoAura file open in front; the
editor serves the MCP on 127.0.0.1:9791. The editor is sandboxed, so art is
sent as data URIs and the export comes back inline.
"""

import base64
import json
import math
import os
import subprocess
import sys

URL = "http://127.0.0.1:9791/mcp"
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RIV = os.path.join(REPO, "Coherence", "Otto", "OttoAura.riv")

FILE_NAME = "OttoAura"
ARTBOARD = "OttoAura"
MACHINE = "OttoAura"
W, H = 664, 744
BASE_X, BASE_Y = 332, 649          # his body's bottom centre on the canvas
FPS = 60

# Names the exported binary must contain, or the rig never left the editor.
REQUIRED = [b"OttoAura", b"stage", b"S1", b"S7", b"Float", b"Aura", b"Bugs"]

# Core property keys (query_property_keys; stable for a file).
K = dict(x=13, y=14, rotation=15, scaleX=16, scaleY=17, opacity=18,
         width=7, height=8, assetId=206, exportType=358, inExport=801,
         trimStart=114, trimEnd=115, trimOffset=116)


# ------------------------------------------------------------------ MCP

def _post(body, timeout):
    hdr = ["-H", "Content-Type: application/json",
           "-H", "Accept: application/json, text/event-stream"]
    return subprocess.run(["curl", "-s", "-N", "-m", str(timeout), URL] + hdr +
                          ["--data-binary", body], capture_output=True, text=True).stdout


def rpc(payload, timeout=300):
    out = _post(payload, timeout)
    if "not initialized" in out:
        _post('{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":'
              '"2025-03-26","capabilities":{},"clientInfo":{"name":"otto_aura_rig","version":"1"}}}', 20)
        _post('{"jsonrpc":"2.0","method":"notifications/initialized"}', 20)
        out = _post(payload, timeout)
    for line in out.splitlines():
        line = line[6:].strip() if line.startswith("data: ") else line.strip()
        if line.startswith("{"):
            d = json.loads(line)
            if "error" in d:
                sys.exit("Rive refused the call: %s" % d["error"])
            return d["result"]
    sys.exit("No answer from the Rive editor. Is it open, with OttoAura in front?")


def call(tool, args, timeout=300):
    r = rpc(json.dumps({"jsonrpc": "2.0", "id": 1, "method": "tools/call",
                        "params": {"name": tool, "arguments": args}}), timeout)
    c = (r.get("content") or [{}])[0]
    text = c.get("text", "")
    if r.get("isError"):
        sys.exit("Rive said (%s): %s" % (tool, text[:1500]))
    try:
        return json.loads(text)
    except ValueError:
        return text


def setp(values):
    """{objectId: {key-name-or-int: value}} -> set_property_values."""
    out = {}
    for oid, props in values.items():
        out[oid] = {str(K.get(k, k)): v for k, v in props.items()}
    return call("set_property_values", {"propertyValues": out})


def ids_of(result, key="objects"):
    return [o["id"] for o in result.get(key, [])]


# ------------------------------------------------------------------ art

def upload(path, name):
    with open(path, "rb") as fh:
        b64 = base64.b64encode(fh.read()).decode()
    a = call("upload_asset", {"file": "data:image/png;name=%s.png;base64,%s" % (name, b64),
                              "name": name})["asset"]
    # Uploaded images default to HOSTED and excluded from export; the .riv
    # then ships without pixels (CLAUDE.md). Embed them.
    setp({a["id"]: {"exportType": 0, "inExport": True}})
    return a


def image(asset_id, parent, name, x, y):
    r = call("assets_tool", {"command": "addImageInstance",
                             "data": {"addImageInstance": {"assetId": asset_id, "parentId": parent,
                                                           "name": name, "x": x, "y": y}}})
    return r.get("id") or r.get("objectId") or r["image"]["id"]


def group(name, parent, x=0, y=0):
    r = call("group_editor", {"name": name, "parentId": parent, "x": x, "y": y})
    return r.get("id") or r.get("groupId") or r["group"]["id"]


def ellipse_arc(rx, ry, upper):
    """Half an ellipse as two cubic quarter-arcs. Lower half runs right to left
    (the front of a ring round his middle), upper half left to right (the
    back), so a light travelling the lower then the upper goes all the way
    round."""
    k = 0.5523
    if not upper:
        return [dict(commandType="moveTo", x=rx, y=0),
                dict(commandType="cubicTo", control1X=rx, control1Y=k * ry,
                     control2X=k * rx, control2Y=ry, endX=0, endY=ry),
                dict(commandType="cubicTo", control1X=-k * rx, control1Y=ry,
                     control2X=-rx, control2Y=k * ry, endX=-rx, endY=0)]
    return [dict(commandType="moveTo", x=-rx, y=0),
            dict(commandType="cubicTo", control1X=-rx, control1Y=-k * ry,
                 control2X=-k * rx, control2Y=-ry, endX=0, endY=-ry),
            dict(commandType="cubicTo", control1X=k * rx, control1Y=-ry,
                 control2X=rx, control2Y=-k * ry, endX=rx, endY=0)]


def leaf_path(length=46, width=20):
    """A lens with two pointed tips: reads as a leaf where an ellipse reads as
    a blob (CLAUDE.md, the branch leaves)."""
    h, w = length / 2, width / 2
    return [dict(commandType="moveTo", x=0, y=-h),
            dict(commandType="cubicTo", control1X=w * 1.3, control1Y=-h * 0.45,
                 control2X=w * 1.1, control2Y=h * 0.55, endX=0, endY=h),
            dict(commandType="cubicTo", control1X=-w * 1.1, control1Y=h * 0.55,
                 control2X=-w * 1.3, control2Y=-h * 0.45, endX=0, endY=-h),
            dict(commandType="close")]


# ------------------------------------------------------------------ commands

def check_file(expect_empty):
    info = call("session_info", {})
    if info.get("activeFileName") != FILE_NAME:
        sys.exit("The file in front is '%s'. Open %s in Rive and bring it to the front."
                 % (info.get("activeFileName"), FILE_NAME))
    boards = call("open_file_editor", {"command": "listArtboards",
                                       "data": {"listArtboards": {}}})["artboards"]
    if expect_empty and len(boards) > 1:
        sys.exit("A new OttoAura file should hold one default artboard; it has %d." % len(boards))
    return boards


def export():
    r = rpc(json.dumps({"jsonrpc": "2.0", "id": 1, "method": "tools/call",
                        "params": {"name": "export_file",
                                   "arguments": {"format": "riv", "destination": "/tmp",
                                                 "inline_base64": True}}}))
    text = r["content"][0].get("text", "")
    d = json.loads(text)
    raw = base64.b64decode(d.get("data") or d.get("base64"))
    missing = [n.decode() for n in REQUIRED if raw.count(n) == 0]
    if missing:
        sys.exit("Export is missing %s. The rig did not leave the editor; do NOT ship it."
                 % ", ".join(missing))
    with open(RIV, "wb") as fh:
        fh.write(raw)
    print("wrote %s (%d KB); every rig name present" % (RIV, len(raw) // 1024))


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    cmd = sys.argv[1]
    if cmd == "export":
        check_file(False)
        export()
    else:
        sys.exit("'%s': build and swap are run step by step from the session that wrote "
                 "them; see the docstring for what the rig contains." % cmd)
