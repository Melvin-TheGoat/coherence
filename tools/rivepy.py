"""Tiny client for the Rive editor's MCP server (127.0.0.1:9791).

The editor serves MCP over plain HTTP JSON-RPC. Newer editors hand back an\nmcp-session-id on initialize, which every later call must carry.
"""
import json, urllib.request, urllib.error

URL = "http://127.0.0.1:9791/mcp"
_ready = False
_id = 0
_session = None


def _post(msg):
    global _session
    headers = {"Content-Type": "application/json", "Accept": "application/json, text/event-stream"}
    if _session:
        headers["mcp-session-id"] = _session
    req = urllib.request.Request(URL, data=json.dumps(msg).encode(), headers=headers)
    with urllib.request.urlopen(req, timeout=600) as r:
        _session = r.headers.get("mcp-session-id") or _session
        body = r.read().decode()
    if not body.strip():
        return None
    if body.lstrip().startswith("event:") or body.lstrip().startswith("data:"):
        body = "\n".join(l[5:] for l in body.splitlines() if l.startswith("data:"))
    return json.loads(body)


def _init():
    global _ready
    if _ready:
        return
    _post({"jsonrpc": "2.0", "id": 0, "method": "initialize",
           "params": {"protocolVersion": "2025-03-26", "capabilities": {}, "clientInfo": {"name": "rivepy", "version": "1"}}})
    try:
        _post({"jsonrpc": "2.0", "method": "notifications/initialized"})
    except urllib.error.HTTPError:
        pass  # the editor answers a notification with 400; it is accepted anyway
    _ready = True


def call(tool, args):
    """Calls a Rive MCP tool and returns its parsed result (JSON when it is JSON)."""
    global _id
    _init()
    _id += 1
    r = _post({"jsonrpc": "2.0", "id": _id, "method": "tools/call", "params": {"name": tool, "arguments": args}})
    if "error" in r:
        raise RuntimeError(r["error"])
    res = r["result"]
    sc = res.get("structuredContent")
    text = "".join(c.get("text", "") for c in res.get("content", []) if c.get("type") == "text")
    try:
        return json.loads(text)
    except Exception:
        return sc if sc is not None else text
