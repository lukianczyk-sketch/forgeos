"""Who can see your screen right now.

On ForgeOS (KDE on Wayland) no program can see the screen by itself: it must ask, and KWin then sends the
picture through PipeWire as a "kwin-screencast" stream. pw-dump lists them, so ANY screen sharing is
seen here - a remote-control app, a video call, or a website showing your screen to someone.
"""
import json

from . import clean, run

SKIP = ("plasmashell", "kwin_wayland", "xdg-desktop-portal-kde", "pipewire", "wireplumber")


def _props(obj):
    return (obj.get("info") or {}).get("props") or {}


def watchers(dump=None):
    """[{'key', 'name', 'pid'}] for every program receiving a picture of the screen now."""
    if dump is None:
        code, out = run(["pw-dump"], 10)
        try:
            dump = json.loads(out) if code == 0 else []
        except ValueError:
            dump = []
    if not isinstance(dump, list):
        return []
    clients = {str(o.get("id")): _props(o) for o in dump if isinstance(o, dict) and o.get("type") == "PipeWire:Interface:Client"}
    nodes = {str(o.get("id")): o for o in dump if isinstance(o, dict) and o.get("type") == "PipeWire:Interface:Node"}
    found = {}
    for o in dump:
        if not isinstance(o, dict) or o.get("type") != "PipeWire:Interface:Link":
            continue
        link = o.get("info") or {}
        src = _props(nodes.get(str(link.get("output-node-id")), {}))
        dst = nodes.get(str(link.get("input-node-id")))
        if dst is None or (dst.get("info") or {}).get("state") != "running":
            continue
        if src.get("media.class") != "Stream/Output/Video" or not str(src.get("media.name", "")).startswith("kwin-screencast"):
            continue
        p = _props(dst)
        c = clients.get(str(p.get("client.id", "")), {})
        key = (c.get("pipewire.access.portal.app_id") or p.get("pipewire.access.portal.app_id")
               or p.get("application.process.binary") or c.get("application.process.binary")
               or p.get("application.name") or c.get("application.name") or "unknown")
        if key in SKIP:
            continue
        name = p.get("application.name") or c.get("application.name") or key
        pid = c.get("application.process.id") or p.get("application.process.id") or 0
        try:
            pid = int(pid)
        except (TypeError, ValueError):
            pid = 0
        found.setdefault(key, {"key": clean(key, 80), "name": clean(name, 60), "pid": pid})
    return sorted(found.values(), key=lambda w: w["key"])
