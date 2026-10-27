"""What GhostFinder remembers (all in this user's own folders): the "it's mine" list, tracker
sightings for "is it following me?", the last sweep, trips and the saved report."""
import json
import os
import time

from . import data_dir, now, report_file, safe_file

DAY = 24 * 3600
FOLLOW_SIGHTINGS, FOLLOW_MINUTES, FOLLOW_PLACES = 3, 60, 2  # AirGuard-style, laptop sized
ALERT_GAP = 4 * 3600


def load_safe():
    """{id: name} of devices and trackers the user said are theirs."""
    safe = {}
    try:
        with open(safe_file(), encoding="utf-8") as f:
            for line in f:
                key, _, name = line.rstrip("\n").partition("\t")
                if key:
                    safe[key.upper()] = name
    except OSError:
        pass
    return safe


def save_safe(safe):
    path = safe_file()
    with open(path + ".new", "w", encoding="utf-8") as f:
        for key in sorted(safe):
            f.write("%s\t%s\n" % (key, " ".join(safe[key].split())))
    os.replace(path + ".new", path)


def _path(name):
    return os.path.join(data_dir(), name)


def read_json(name, default):
    try:
        with open(_path(name), encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def write_json(name, value):
    with open(_path(name) + ".new", "w", encoding="utf-8") as f:
        json.dump(value, f)
    os.replace(_path(name) + ".new", _path(name))


def add_sightings(trackers, place):
    """Remember trackers heard now, at this place; forget sightings older than a day."""
    t = now()
    rows = [r for r in read_sightings() if t - r["t"] < DAY]
    rows += [{"t": t, "id": k["id"], "label": k["label"], "place": place} for k in trackers]
    with open(_path("sightings.jsonl.new"), "w", encoding="utf-8") as f:
        for r in rows:
            f.write(json.dumps(r) + "\n")
    os.replace(_path("sightings.jsonl.new"), _path("sightings.jsonl"))


def read_sightings():
    rows = []
    try:
        with open(_path("sightings.jsonl"), encoding="utf-8") as f:
            for line in f:
                try:
                    rows.append(json.loads(line))
                except ValueError:
                    pass
    except OSError:
        pass
    return rows


def followers():
    """{id: (label, sightings, minutes, places)} for trackers heard 3+ times, over an hour or more,
    in 2+ places in the last day: the pattern of a tracker travelling with you."""
    t, safe, seen = now(), load_safe(), {}
    for r in read_sightings():
        if t - r["t"] < DAY and r["id"].upper() not in safe:
            seen.setdefault(r["id"].upper(), []).append(r)
    out = {}
    for key, rows in seen.items():
        minutes = int((max(r["t"] for r in rows) - min(r["t"] for r in rows)) / 60)
        places = len({r["place"] for r in rows})
        if len(rows) >= FOLLOW_SIGHTINGS and minutes >= FOLLOW_MINUTES and places >= FOLLOW_PLACES:
            out[key] = (rows[-1]["label"], len(rows), minutes, places)
    return out


def should_alert(key):
    """True once every 4 hours per tracker (and remembers that it alerted)."""
    alerted = read_json("alerted.json", {})
    if now() - alerted.get(key, 0) < ALERT_GAP:
        return False
    alerted[key] = now()
    write_json("alerted.json", alerted)
    return True


def report(title, lines):
    """Add an entry to ~/Documents/GhostFinder/GhostFinder report.txt."""
    path = report_file()
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "a", encoding="utf-8") as f:
        f.write("%s  %s\n" % (time.strftime("%Y-%m-%d %H:%M", time.localtime(now())), title))
        for line in lines:
            f.write("   " + line + "\n")
        f.write("\n")
    return path
