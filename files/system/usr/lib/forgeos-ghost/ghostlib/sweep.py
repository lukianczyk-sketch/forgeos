"""One full sweep: devices on the network, camera checks, spy-camera Wi-Fi, Bluetooth trackers."""
import threading

from . import ble, names, net, now, store, trackers, wifi

ORDER = {"red": 0, "yellow": 1, "green": 2}
VERDICT = {
    "red": "RED - possible camera or tracker found. Look at the red items.",
    "yellow": "YELLOW - nothing for sure, but take a look at the yellow items.",
    "green": "GREEN - all clear. No cameras or trackers found.",
}


def clean(text):
    """Device and Wi-Fi names come from strangers: one line, no tags, not too long."""
    return " ".join(str(text).replace("<", "").replace(">", "").split())[:60]


def item(key, level, what, kind, hunt="", detail=""):
    return {"id": key, "level": level, "what": what, "kind": kind, "hunt": hunt, "detail": detail}


def network_items(safe):
    mine = net.my_network()
    if not mine:
        return None
    dev, me, netw, gateway = mine
    net.wake(netw, me)
    found = net.neighbors(dev)
    box = {}
    t = threading.Thread(target=lambda: box.update(cams=net.onvif_cameras()), daemon=True)
    t.start()
    wanted = net.ports()
    opened = net.open_ports([a for a, _ in found], wanted)
    svcs = names.services()
    t.join(5)
    cams = box.get("cams", set())
    out = []
    for addr, mac in found:
        kind, words, made = names.describe(mac, svcs.get(addr, []), addr == gateway)
        why = ["answers the network-camera call (ONVIF)"] if addr in cams else []
        why += ["port %d open: %s" % (p, wanted[p]) for p in opened.get(addr, [])]
        if why and kind != "camera":
            kind, words = "camera", "camera" + (" made by " + made if made else "")
        label = clean(svcs[addr][0][0]) if svcs.get(addr) else ""
        what = "%s - %s%s" % (words, addr, ' "%s"' % label if label else "")
        detail = "; ".join(why + (["maker: " + made] if made else []))
        key = mac.upper()
        if kind == "router":
            out.append(item(key, "green", what, kind, detail=detail))
        elif key in safe:
            out.append(item(key, "green", "yours: " + (safe[key] or what), kind, detail=detail))
        elif kind == "camera":
            out.append(item(key, "red", "Camera on this network: " + what, kind, detail=detail))
        else:
            out.append(item(key, "yellow", "New device: " + what, kind, detail=detail))
    return out


def hotspot_items(nets, safe):
    out = []
    for name, bssid, sig in wifi.spy_hotspots(nets):
        key = "WIFI:" + bssid
        what = 'Spy-camera Wi-Fi "%s" nearby - signal %d%%' % (clean(name), sig)
        if key in safe:
            out.append(item(key, "green", "yours: " + (safe[key] or what), "hotspot", "wifi"))
        else:
            out.append(item(key, "red" if sig >= 40 else "yellow", what, "hotspot", "wifi"))
    return out


def tracker_items(devs, safe, place):
    out, away = [], []
    for d in devs:
        k = trackers.classify(d)
        if not k:
            continue
        key = d["id"].upper()
        if key in safe:
            out.append(item(key, "green", "yours: " + (safe[key] or k["label"]), k["kind"], "ble"))
            continue
        away.append({"id": key, "label": k["label"]})
        where = "away from its owner" if k["sure"] else "nearby (this brand can't say if its owner is with it)"
        what = "%s %s - %s" % (k["label"], where, trackers.distance(d["rssi"]))
        out.append(item(key, "yellow", what, k["kind"], "ble", k["extra"]))
    store.add_sightings(away, place)
    follow = store.followers()
    for i in out:
        if i["id"] in follow:
            label, times, minutes, places = follow[i["id"]]
            i["level"] = "red"
            i["what"] = "%s may be FOLLOWING you - heard %d times over %d minutes in %d places" % (
                label, times, minutes, places)
    return out


def sweep(secs=12, use_ble=True):
    """Run everything at once; returns the result that is also saved as last-sweep.json."""
    safe = store.load_safe()
    box = {"bt": "skipped", "devs": []}

    def listen():
        try:
            box["devs"] = ble.scan(secs)
            box["bt"] = "on"
        except ble.BleError as e:
            box["bt"] = str(e)

    t = threading.Thread(target=listen, daemon=True)
    if use_ble:
        t.start()
    nets = wifi.networks()
    place = wifi.place(nets)
    netitems = network_items(safe)
    items = (netitems or []) + hotspot_items(nets, safe)
    if use_ble:
        t.join(secs + 30)
    items += tracker_items(box["devs"], safe, place)
    items.sort(key=lambda i: (ORDER[i["level"]], i["what"]))
    level = items[0]["level"] if items else "green"
    notes = []
    if box["bt"] != "on":
        notes.append({"off": "Bluetooth is off, so trackers were not checked.",
                      "none": "This PC has no Bluetooth, so trackers were not checked."}.get(
                          box["bt"], "Trackers were not checked."))
    if netitems is None:
        notes.append("Not connected to a network, so cameras on the network were not checked.")
    result = {"time": now(), "place": place, "level": level, "verdict": VERDICT[level],
              "notes": notes, "items": items}
    store.write_json("last-sweep.json", result)
    return result
