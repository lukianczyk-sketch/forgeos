"""Adding the "From Windows" bookmarks folder to Brave (the ForgeOS browser).

Brave must be closed while its bookmarks file is changed. A copy of Brave's file is kept first
(Bookmarks.before-moving-day), and a second run replaces the folder an earlier run made.
"""
import json
import os
import shutil
import time
import uuid

from . import BRAVE

MARK = {"forgeos": "movingday"}


def brave_open():
    return os.path.lexists(os.path.join(BRAVE, "SingletonLock"))


def _stamp():
    return str(int((time.time() + 11644473600) * 1000000))  # microseconds since 1601, Chromium's clock


def _to_brave(n, ids):
    ids[0] += 1
    out = {"date_added": _stamp(), "guid": str(uuid.uuid4()), "id": str(ids[0]), "name": n["name"]}
    if "children" in n:
        out.update(type="folder", date_modified="0", children=[_to_brave(c, ids) for c in n["children"]])
    else:
        out.update(type="url", url=n["url"])
    return out


def _max_id(n):
    return max([int(n.get("id", 0) or 0)] + [_max_id(c) for c in n.get("children", [])])


def empty_file():
    def root(i, name, guid):
        return {"children": [], "date_added": "0", "date_modified": "0", "guid": guid, "id": str(i), "name": name, "type": "folder"}
    return {"roots": {"bookmark_bar": root(1, "Bookmarks bar", "0bc5d13f-2cba-5d74-951f-3f233fe6c908"),
                      "other": root(2, "Other bookmarks", "82b081ec-3dd3-529c-8475-ab6c344590dd"),
                      "synced": root(3, "Mobile bookmarks", "4cf2e351-0e85-532b-bb37-df045d8f8d0f")}, "version": 1}


def add_to_brave(root):
    """Put the folder on Brave's bookmarks bar (replacing the one an earlier run made). True when done."""
    if brave_open():
        return False
    path = os.path.join(BRAVE, "Default", "Bookmarks")
    if os.path.isfile(path):
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        shutil.copy2(path, path + ".before-moving-day")
    else:
        data = empty_file()
    bar = data["roots"]["bookmark_bar"]
    bar["children"] = [c for c in bar.get("children", []) if c.get("meta_info") != MARK]
    ids = [max(_max_id(r) for r in data["roots"].values() if isinstance(r, dict))]
    node = _to_brave(root, ids)
    node["meta_info"] = dict(MARK)
    bar["children"].append(node)
    data.pop("checksum", None)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path + ".moving", "w", encoding="utf-8") as f:
        json.dump(data, f, indent=3)
    os.replace(path + ".moving", path)
    return True
