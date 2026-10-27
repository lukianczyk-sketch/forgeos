"""Bluetooth: listen for nearby Bluetooth Low Energy signals through BlueZ (python3-dbus).

Only listens; never connects to or pairs with anything. Discovery stops when we stop or exit.
Tests: FORGEOS_GHOST_BLE_FAKE = a JSON file: {"power": "on|off|none", "polls": [[device, ...], ...]}.
"""
import json
import time

from . import env
from .trackers import short


class BleError(Exception):
    """Bluetooth is off ("off") or this PC has none ("none")."""


def _fake():
    path = env("FORGEOS_GHOST_BLE_FAKE")
    if not path:
        return None
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def _bus():
    import dbus  # python3-dbus
    if env("FORGEOS_GHOST_BUS") == "session":  # tests run a fake BlueZ on a private bus
        return dbus, dbus.SessionBus()
    return dbus, dbus.SystemBus()


def _adapter():
    """(dbus module, bus, adapter path, adapter properties) or BleError."""
    try:
        dbus, bus = _bus()
        om = dbus.Interface(bus.get_object("org.bluez", "/"), "org.freedesktop.DBus.ObjectManager")
        objs = om.GetManagedObjects()
    except Exception:  # no python3-dbus, no BlueZ, no adapter
        raise BleError("none")
    for path, ifaces in sorted(objs.items()):
        if "org.bluez.Adapter1" in ifaces:
            return dbus, bus, path, ifaces["org.bluez.Adapter1"]
    raise BleError("none")


def status():
    """'on', 'off' or 'none'."""
    fake = _fake()
    if fake is not None:
        return fake.get("power", "on")
    try:
        props = _adapter()[3]
    except BleError as e:
        return str(e)
    return "on" if bool(props.get("Powered")) else "off"


def power(on):
    """Turn Bluetooth on or off. False if it is blocked (airplane mode / Panic Button) or missing."""
    fake = _fake()
    if fake is not None:
        if fake.get("power") == "none" or fake.get("blocked"):
            return False
        fake["power"] = "on" if on else "off"
        with open(env("FORGEOS_GHOST_BLE_FAKE"), "w", encoding="utf-8") as f:
            json.dump(fake, f)
        return True
    try:
        dbus, bus, path, _ = _adapter()
        props = dbus.Interface(bus.get_object("org.bluez", path), "org.freedesktop.DBus.Properties")
        props.Set("org.bluez.Adapter1", "Powered", dbus.Boolean(on))
    except Exception:
        return False
    return True


def _plain(path, p):
    mfg = {int(k): bytes(bytearray(v)) for k, v in dict(p.get("ManufacturerData", {})).items()}
    svc = {short(k): bytes(bytearray(v)) for k, v in dict(p.get("ServiceData", {})).items()}
    name = str(p.get("Alias") or p.get("Name") or "")
    return {"id": str(p.get("Address", path)).upper(), "name": name, "rssi": int(p["RSSI"]),
            "mfg": mfg, "svc": svc, "uuids": [short(u) for u in p.get("UUIDs", [])]}


def _from_json(d):
    return {"id": d["id"].upper(), "name": d.get("name", ""), "rssi": int(d["rssi"]),
            "mfg": {int(k, 0): bytes.fromhex(v) for k, v in d.get("mfg", {}).items()},
            "svc": {short(k): bytes.fromhex(v) for k, v in d.get("svc", {}).items()},
            "uuids": [short(u) for u in d.get("uuids", [])]}


def scan(secs, each=None):
    """Listen for about `secs` seconds (one look per second). Returns every device heard
    (strongest signal kept). each(devices heard this second) may return True to stop early."""
    fake = _fake()
    seen = {}

    def look(devs):
        for d in devs:
            old = seen.get(d["id"])
            if old is None or d["rssi"] > old["rssi"]:
                seen[d["id"]] = d
        return bool(each and each(devs))

    if fake is not None:
        if fake.get("power", "on") != "on":
            raise BleError(fake.get("power"))
        polls = fake.get("polls") or [[]]
        for i in range(max(1, int(secs))):
            if look([_from_json(d) for d in polls[min(i, len(polls) - 1)]]):
                break
        return list(seen.values())
    dbus, bus, path, props = _adapter()
    if not props.get("Powered"):
        raise BleError("off")
    adapter = dbus.Interface(bus.get_object("org.bluez", path), "org.bluez.Adapter1")
    om = dbus.Interface(bus.get_object("org.bluez", "/"), "org.freedesktop.DBus.ObjectManager")
    try:  # LE only, and report repeats so the signal strength stays fresh for the hunt
        adapter.SetDiscoveryFilter({"Transport": "le", "DuplicateData": dbus.Boolean(True)})
    except dbus.DBusException:
        pass
    try:
        adapter.StartDiscovery()
    except dbus.DBusException:
        pass  # someone else is already scanning: fine, we still hear everything
    try:
        for _ in range(max(1, int(secs))):
            time.sleep(1)
            objs = om.GetManagedObjects()
            devs = [_plain(p, i["org.bluez.Device1"]) for p, i in objs.items()
                    if "org.bluez.Device1" in i and "RSSI" in i["org.bluez.Device1"]]
            if look(devs):
                break
    finally:
        try:
            adapter.StopDiscovery()
        except dbus.DBusException:
            pass
    return list(seen.values())
