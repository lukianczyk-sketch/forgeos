"""forgeos-ghost commands. Exit: 0 done, 1 not found, 3 wrong use, 4 Bluetooth off or missing."""
import math
import os
import struct
import sys
import wave

from . import advice, ble, home, store, trackers, wifi

USAGE = """Usage: forgeos-ghost sweep [--secs N] [--no-bt]
       forgeos-ghost info ID | hunt ID [--secs N]
       forgeos-ghost safe add ID [NAME] | safe remove ID | safe list | known-all
       forgeos-ghost trip start | trip tick | trip stop
       forgeos-ghost watch-tick | bt on|off|status | checklist | beep-file"""
TRACKER_KINDS = set(advice.HOW)


def usage():
    print(USAGE, file=sys.stderr)
    return 3


def secs(args, default):
    if "--secs" in args:
        i = args.index("--secs")
        if i + 1 < len(args) and args[i + 1].isdigit():
            return int(args[i + 1])
    return default


def show(result):
    print("GhostFinder - see who's watching.")
    print(result["verdict"])
    for note in result["notes"]:
        print("Note: " + note)
    for i in result["items"]:
        if i["level"] != "green":
            print("- %s: %s" % (i["level"].upper(), i["what"]))
    green = sum(1 for i in result["items"] if i["level"] == "green")
    if green:
        print("%d known or safe device(s) look fine." % green)
    print("VERDICT\t%s" % result["level"])
    for note in result["notes"]:
        print("NOTE\t" + note)
    for i in result["items"]:
        print("\t".join(["ITEM", i["level"], i["id"], i["hunt"] or "-", i["what"]]))


def find(key):
    for i in store.read_json("last-sweep.json", {}).get("items", []):
        if i["id"] == key.upper():
            return i
    return None


def hunt(key, limit):
    """One line per second: LEVEL <0-100> <words>. Hotter = closer."""
    key, last, lost = key.upper(), 0, 0
    if key.startswith("WIFI:"):
        for _ in range(limit):
            sig = wifi.signal(key[5:])
            last = sig if sig is not None else max(0, last - 10)
            print("LEVEL\t%d\t%s" % (last, trackers.words(last) if sig is not None else "searching..."), flush=True)
        return 0

    def each(devs):
        nonlocal last, lost
        hit = [d for d in devs if d["id"] == key]
        lost = 0 if hit else lost + 1
        if hit:
            last = trackers.level(hit[0]["rssi"])
        elif lost >= 10:
            last = 0
        print("LEVEL\t%d\t%s" % (last, trackers.words(last) if hit else
                                 "lost the signal - move around" if lost >= 10 else "searching..."), flush=True)
        return False
    try:
        ble.scan(limit, each)
    except ble.BleError:
        print("Bluetooth is off. Turn it on to hunt a tracker.", file=sys.stderr)
        return 4
    return 0


def beep_file():
    """A short beep for the hunt meter (made here, so no sound file is needed)."""
    path = home(".cache", "forgeos", "ghost-beep.wav")
    if not os.path.exists(path):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with wave.open(path, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(22050)
            w.writeframes(b"".join(struct.pack("<h", int(9000 * math.sin(2 * math.pi * 1760 * n / 22050)))
                                   for n in range(2205)))
    print(path)
    return 0
