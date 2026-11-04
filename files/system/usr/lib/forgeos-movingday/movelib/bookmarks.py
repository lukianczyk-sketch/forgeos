"""Bookmarks from Chrome, Edge, Brave and Firefox on Windows -> one "From Windows" folder in Brave.

A node is {"name": ..., "url": ...} or {"name": ..., "children": [...]}. Brave must be closed while its
bookmarks file is changed (brave.py); the bookmarks file in Documents is always made too, so any
browser can import it.
"""
import html
import json
import os
import sqlite3

from . import HOME

FOLDER = "From Windows"
HTML_NAME = "Bookmarks from Windows.html"


def _chromium_node(n):
    if n.get("type") == "url" and str(n.get("url", "")).startswith(("http://", "https://", "ftp://")):
        return {"name": n.get("name") or n["url"], "url": n["url"]}
    if n.get("type") == "folder":
        kids = [k for k in (_chromium_node(c) for c in n.get("children", [])) if k]
        return {"name": n.get("name") or "Folder", "children": kids} if kids else None
    return None


def read_chromium(path):
    with open(path, encoding="utf-8") as f:
        roots = json.load(f).get("roots", {})
    out = []
    for key in ("bookmark_bar", "other", "synced"):
        node = _chromium_node(roots.get(key, {"type": "folder", "children": []}))
        if node:
            out.append(node)
    return out


def read_firefox(path):
    db = sqlite3.connect("file:%s?mode=ro&immutable=1" % path, uri=True)
    try:
        rows = db.execute("SELECT b.id, b.type, b.parent, b.title, p.url, b.guid FROM moz_bookmarks b "
                          "LEFT JOIN moz_places p ON b.fk = p.id ORDER BY b.parent, b.position").fetchall()
    finally:
        db.close()
    kids = {}
    for bid, typ, parent, title, url, guid in rows:
        kids.setdefault(parent, []).append((bid, typ, title, url, guid))

    def build(bid, title):
        out = []
        for cid, typ, ctitle, url, _g in kids.get(bid, []):
            if typ == 1 and url and url.startswith(("http://", "https://", "ftp://")):
                out.append({"name": ctitle or url, "url": url})
            elif typ == 2:
                sub = build(cid, ctitle)
                if sub:
                    out.append(sub)
        return {"name": title or "Folder", "children": out} if out else None
    tops = [build(cid, {"toolbar_____": "Bookmarks Toolbar", "menu________": "Bookmarks Menu",
                        "unfiled_____": "Other Bookmarks", "mobile______": "Mobile Bookmarks"}[g])
            for cid, typ, _t, _u, g in kids.get(1, []) if g in ("toolbar_____", "menu________", "unfiled_____", "mobile______")]
    return [t for t in tops if t]


def collect(found):
    """found = [(label, kind, file)] -> ({"name": "From Windows", ...}, bookmark count, problems)."""
    tree, bad = [], []
    for label, kind, path in found:
        try:
            nodes = read_chromium(path) if kind == "chromium" else read_firefox(path)
        except (OSError, ValueError, sqlite3.Error):
            bad.append(label)
            continue
        if nodes:
            tree.append({"name": label, "children": nodes})
    return {"name": FOLDER, "children": tree}, count(tree), bad


def count(nodes):
    return sum(count(n["children"]) if "children" in n else 1 for n in nodes)


def write_html(root, folder=None):
    """The Netscape bookmarks file every browser can import. Returns its path."""
    lines = ["<!DOCTYPE NETSCAPE-Bookmark-file-1>", '<META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">',
             "<TITLE>Bookmarks</TITLE>", "<H1>Bookmarks</H1>", "<DL><p>"]

    def add(n, pad):
        if "children" in n:
            lines.append('%s<DT><H3>%s</H3>' % (pad, html.escape(n["name"])))
            lines.append(pad + "<DL><p>")
            for c in n["children"]:
                add(c, pad + "    ")
            lines.append(pad + "</DL><p>")
        else:
            lines.append('%s<DT><A HREF="%s">%s</A>' % (pad, html.escape(n["url"]), html.escape(n["name"])))
    add(root, "    ")
    lines.append("</DL><p>")
    folder = folder or os.path.join(HOME, "Documents")
    os.makedirs(folder, exist_ok=True)
    path = os.path.join(folder, HTML_NAME)
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    return path
