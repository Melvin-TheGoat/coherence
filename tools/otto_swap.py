#!/usr/bin/env python3
"""Put a new Otto drawing into the Rive rig and out to the app, in one step.

    python3 tools/otto_swap.py mockups/otto-v3/otto-wave.png
    python3 tools/otto_swap.py --dry-run          # just say what it would do

The rig (timelines, state machine, view model) never changes; only the art
inside it does. So a redesign round is: draw him, run this, look at the
simulator. Nothing here touches Swift.

WHAT IT DOES, in the order it matters:
  1. Uploads the PNG to the open Rive file as an embedded asset.
  2. Points every image in the rig's Solo at it.
  3. Sits his feet on the node (y = -height / 2) and grows the artboard
     around the new drawing.
  4. Deletes the assets nothing references any more, because the .riv
     EMBEDS its art and would otherwise carry every old Otto forever.
  5. Exports and writes Coherence/Otto/Otto.riv.
  6. Reads the exported bytes back and fails loudly if the rig's names are
     not in them.

WHY STEP 6 EXISTS: the Rive editor reported this rig correctly for a whole
day while its export contained none of it, so the editor cannot be trusted
to confirm its own export. See CLAUDE.md, "THE RIVE EXPORT ONLY EVER
EMITTED THE FIRST ARTBOARD". The same section explains why the file must
hold exactly one artboard; this script refuses to run if a second appears,
since that silently breaks the export again.

REQUIRES the Rive desktop editor open on the Otto file, which serves the
MCP on 127.0.0.1:9791. Nothing else.
"""

import base64
import json
import os
import subprocess
import sys

URL = "http://127.0.0.1:9791/mcp"
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RIV = os.path.join(REPO, "Coherence", "Otto", "Otto.riv")

ARTBOARD = "Otto"
STATE_MACHINE = "Otto"
# Names the export must contain, or the rig did not make it out of the editor.
REQUIRED = [b"Otto", b"Breathe", b"Wave", b"Talk", b"Still", b"wave", b"talking"]

# Property keys, read off the editor with query_property_keys. They are
# stable for a file; re-read them if a call starts failing.
K_X, K_Y, K_W, K_H = 13, 14, 7, 8
K_ASSET_ID = 206        # on an Image
K_EXPORT_TYPE = 358     # on an asset: 0 = embedded
K_IN_EXPORT = 801       # on an asset


def rpc(payload, timeout=300):
    """One MCP call. The server keeps no session, so it is initialize,
    notify, call, every time. `curl -N` matters: without it the export's
    body comes back empty."""
    hdr = ["-H", "Content-Type: application/json",
           "-H", "Accept: application/json, text/event-stream"]
    for body in ('{"jsonrpc":"2.0","id":1,"method":"initialize","params":'
                 '{"protocolVersion":"2025-03-26","capabilities":{},'
                 '"clientInfo":{"name":"otto_swap","version":"1"}}}',
                 '{"jsonrpc":"2.0","method":"notifications/initialized"}'):
        subprocess.run(["curl", "-s", "-o", "/dev/null", "-m", "20", URL] + hdr + ["-d", body],
                       check=False)
    out = subprocess.run(["curl", "-s", "-N", "-m", str(timeout), URL] + hdr +
                         ["--data-binary", payload],
                         capture_output=True, text=True, check=False).stdout
    for line in out.splitlines():
        line = line[6:].strip() if line.startswith("data: ") else line.strip()
        if line.startswith("{"):
            d = json.loads(line)
            if "error" in d:
                sys.exit("Rive refused the call: %s" % d["error"].get("message"))
            return d["result"]
    sys.exit("No answer from the Rive editor. Is it open on the Otto file?")


def call(tool, args, timeout=300):
    r = rpc(json.dumps({"jsonrpc": "2.0", "id": 1, "method": "tools/call",
                        "params": {"name": tool, "arguments": args}}), timeout)
    content = r.get("content", [{}])[0]
    if content.get("type") == "image":
        return content
    text = content.get("text", "")
    try:
        return json.loads(text)
    except ValueError:
        sys.exit("Rive said: %s" % text[:400])


def find_images():
    """The Image components under the rig's Solo, and the assets they use."""
    tree = call("get_artboard_hierarchy", {"depth": 6})
    images, assets = [], set()
    for obj in tree.get("objects", []):
        if "Image" in obj.get("types", []):
            images.append(obj["id"])
    if not images:
        sys.exit("No images found on the artboard. Has the rig been rebuilt?")
    vals = call("query_property_values",
                {"propertyKeys": {i: [K_ASSET_ID] for i in images}})
    for i in images:
        a = vals.get("values", {}).get(i, {}).get(str(K_ASSET_ID))
        if a:
            assets.add(a)
    return images, assets


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    dry = "--dry-run" in sys.argv

    open_file = call("session_info", {})
    if not open_file.get("activeFileName"):
        sys.exit("No file open in Rive. Open the Otto file and try again.")
    print("file:      %s" % open_file["activeFileName"])

    boards = call("open_file_editor",
                  {"command": "listArtboards", "data": {"listArtboards": {}}})["artboards"]
    names = [b["name"] for b in boards]
    if names != [ARTBOARD]:
        sys.exit("The file must hold exactly one artboard called '%s'. It has: %s.\n"
                 "A second artboard silently breaks the export (CLAUDE.md)." % (ARTBOARD, names))
    board = boards[0]
    images, old_assets = find_images()
    print("artboard:  %s (%gx%g)" % (board["name"], board["width"], board["height"]))
    print("images:    %s  using assets %s" % (", ".join(images), ", ".join(sorted(old_assets))))

    if dry:
        print("\ndry run, nothing changed.")
        return
    if not args:
        sys.exit("Give me the new PNG: python3 tools/otto_swap.py <path-to-png>")

    png = os.path.abspath(args[0])
    if not os.path.exists(png):
        sys.exit("No such file: %s" % png)

    # The editor is sandboxed and cannot read the repo, so the art goes over
    # as a data URI rather than a path.
    with open(png, "rb") as fh:
        b64 = base64.b64encode(fh.read()).decode()
    name = os.path.splitext(os.path.basename(png))[0]
    print("uploading: %s" % name)
    asset = call("upload_asset",
                 {"file": "data:image/png;name=%s.png;base64,%s" % (name, b64),
                  "name": name})["asset"]
    aid, aw, ah = asset["id"], asset["width"], asset["height"]
    print("           %s  %gx%g" % (aid, aw, ah))

    # His feet sit on the parent node at y = -height / 2. The artboard grows
    # to hold him with a little air above his head.
    width = max(400.0, aw + 16)
    height = ah + 15
    writes = {i: {str(K_X): 0, str(K_Y): -ah / 2.0, str(K_ASSET_ID): aid} for i in images}
    writes[aid] = {str(K_EXPORT_TYPE): 0, str(K_IN_EXPORT): True}
    writes[board["id"]] = {str(K_W): width, str(K_H): height}
    node = call("find_objects", {"name": "Nod"}).get("objects", [])
    if node:
        writes[node[0]["id"]] = {str(K_X): width / 2.0, str(K_Y): height - 10}
    call("set_property_values", {"propertyValues": writes})
    print("placed:    artboard %gx%g, feet on the node" % (width, height))

    stale = [a for a in old_assets if a != aid]
    if stale:
        call("delete_objects", {"objectIds": stale})
        print("deleted:   old art %s" % ", ".join(stale))

    print("exporting...")
    out = call("export_file", {"format": "riv", "destination": REPO, "inline_base64": True})
    raw = base64.b64decode(out.get("data") or out.get("base64"))
    missing = [n.decode() for n in REQUIRED if raw.count(n) == 0]
    if missing:
        sys.exit("Export is missing %s. The rig did not leave the editor; do NOT ship this."
                 % ", ".join(missing))
    with open(RIV, "wb") as fh:
        fh.write(raw)
    print("wrote:     %s (%d KB), every rig name present" % (RIV, len(raw) // 1024))
    print("\nNow: xcodegen generate is not needed. Build and look at Home.")


if __name__ == "__main__":
    main()
