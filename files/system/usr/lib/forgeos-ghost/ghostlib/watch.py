"""Background watch and trip watch: is a tracker travelling with you?"""
import math
import os
import subprocess
import sys

from . import ble, now, store, trackers, wifi


def away(devs, safe):
    out = []
    for d in devs:
        k = trackers.classify(d)
        if k and d["id"] not in safe:
            out.append({"id": d["id"], "label": k["label"]})
    return out


def watch_tick():
    """Background watch (every 10 minutes): listen 15 s; warn if a tracker is travelling with you."""
    if ble.status() != "on":
        return 0  # never turns Bluetooth on by itself
    try:
        found = away(ble.scan(15), store.load_safe())
    except ble.BleError:
        return 0
    store.add_sightings(found, wifi.place())
    for key, (label, times, minutes, places) in sorted(store.followers().items()):
        if store.should_alert(key):
            msg = "A tracker (%s) may be following you: heard %d times over %d minutes in %d places." % (
                label, times, minutes, places)
            store.report("Background watch: possible tracker following you", [msg, "ID: " + key])
            try:
                subprocess.run(["notify-send", "-u", "critical", "-a", "GhostFinder", "-i", "security-medium",
                                "GhostFinder", msg + " Open GhostFinder and sweep to find it."], check=False)
            except OSError:
                pass  # no notifications: it is still in the saved report
            print(msg)
    return 0


def trip(action):
    """Watch a drive: a tracker heard in most checks for 10+ minutes stayed with you."""
    t = now()
    if action == "start":
        store.write_json("trip.json", {"start": t, "scans": 0, "seen": {}})
        return 0
    data = store.read_json("trip.json", None)
    if data is None:
        print("No trip is being watched. Start one with: forgeos-ghost trip start", file=sys.stderr)
        return 1
    if action == "tick":
        try:
            found = away(ble.scan(20), store.load_safe())
        except ble.BleError:
            print("Bluetooth is off. Turn it on to watch a trip.", file=sys.stderr)
            return 4
        data["scans"] += 1
        for k in found:
            first = data["seen"].get(k["id"], [0, t])[1]
            data["seen"][k["id"]] = [data["seen"].get(k["id"], [0])[0] + 1, first, t, k["label"]]
        store.add_sightings(found, wifi.place())
        store.write_json("trip.json", data)
        print("TRIP\t%d" % data["scans"])
        return 0
    os.remove(os.path.join(store.data_dir(), "trip.json"))
    n, bad = data["scans"], []
    for key, (count, first, last, label) in sorted(data["seen"].items()):
        if count >= 3 and count >= math.ceil(n / 2) and last - first >= 600:
            bad.append((key, "%s stayed with you the whole trip (heard in %d of %d checks)" % (label, count, n)))
    if n < 3:
        print("The trip was too short to tell (GhostFinder needs at least 3 checks, about 3 minutes).")
    elif not bad:
        print("GREEN - no tracker stayed with you on this trip (%d checks)." % n)
    for key, what in bad:
        print("RED - " + what)
        print("\t".join(["ITEM", "red", key, "ble", what]))
    store.report("Trip watch: %d checks" % n, [w for _, w in bad] or ["No tracker stayed with you."])
    return 0
