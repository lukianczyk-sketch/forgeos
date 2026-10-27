"""Which Bluetooth signals are item trackers away from their owner (the kind that can follow you).

Facts from AirGuard (SEEMOO, TU Darmstadt) and the IETF DULT tracker standard.
A tracker that is near its owner is ignored: its owner is right there, so it is not following you.
"""

APPLE_KINDS = {
    1: ("airtag", "AirTag"),
    2: ("findmy", "Find My tracker (not made by Apple)"),
    3: ("airpods", "AirPods"),
    0: ("apple", "lost iPhone, iPad or Mac"),
}
BATTERY = {0: "full", 1: "medium", 2: "low", 3: "very low"}


def short(uuid):
    """'0000fd5a-0000-1000-8000-00805f9b34fb' -> 'fd5a'."""
    u = str(uuid).lower()
    if len(u) == 36 and u.startswith("0000") and u.endswith("-0000-1000-8000-00805f9b34fb"):
        return u[4:8]
    return u


def found(kind, label, extra="", sure=True):
    """sure=False: this brand does not say whether its owner is nearby."""
    return {"kind": kind, "label": label, "extra": extra, "sure": sure}


def classify(dev):
    """dev: {"mfg": {company id: bytes}, "svc": {short uuid: bytes}, "uuids": [short uuids]}.
    Returns {"kind", "label", "extra", "sure"} for a tracker away from its owner, else None."""
    mfg, svc, uuids = dev.get("mfg", {}), dev.get("svc", {}), [short(u) for u in dev.get("uuids", [])]
    apple = mfg.get(0x004C)
    if apple and len(apple) >= 3 and apple[0] == 0x12:
        if apple[1] != 0x19:
            return None  # short Find My signal = its owner is nearby
        kind, label = APPLE_KINDS[(apple[2] >> 4) & 3]
        return found(kind, label, "battery " + BATTERY[(apple[2] >> 6) & 3])
    d = svc.get("fcb2")
    if d is not None and len(d) >= 2:
        if d[1] & 1:
            return None  # near-owner bit set
        return found("dult", "item tracker (Android / any brand)")
    d = svc.get("feaa")
    if d and d[0] in (0x40, 0x41):
        if not d[0] & 1:
            return None  # was with its owner in the last 4 hours
        return found("google", "Google Find My Device tracker")
    d = svc.get("fd5a")
    if d:
        state = ((d[0] >> 2) & 1, (d[0] >> 1) & 1, d[0] & 1)
        if state not in ((0, 1, 1), (0, 1, 0)):
            return None  # connected to its owner's phone, or only just left it
        return found("smarttag", "Samsung SmartTag")
    if "fd69" in svc:
        return found("galaxy", "lost Samsung phone or watch")
    if "feed" in svc or "feed" in uuids:
        return found("tile", "Tile tracker", sure=False)
    if "fe33" in svc or "fe33" in uuids:
        return found("chipolo", "Chipolo tracker", sure=False)
    if "fa25" in svc or "fa25" in uuids:
        return found("pebblebee", "Pebblebee tracker", sure=False)
    return None


def level(rssi):
    """Signal strength (dBm, about -100 far .. -40 touching) -> 0..100."""
    return max(0, min(100, int((rssi + 100) * 100 / 60)))


def words(lvl):
    if lvl >= 85:
        return "RIGHT ON IT"
    if lvl >= 65:
        return "HOT"
    if lvl >= 45:
        return "WARM"
    if lvl >= 25:
        return "COOL"
    return "COLD"


def distance(rssi):
    """Plain words for how close a Bluetooth signal is."""
    if rssi is None:
        return "signal strength unknown"
    if rssi >= -60:
        return "very close (a few feet)"
    if rssi >= -75:
        return "close (same room)"
    return "farther away (next room or outside)"
