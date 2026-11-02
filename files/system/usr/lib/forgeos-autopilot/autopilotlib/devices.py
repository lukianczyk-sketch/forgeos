"""Device Check: every important part of the PC and the driver it uses (like Device Manager's yellow "!").

Read-only: looks at /sys (no password, nothing changed). PCI cards (graphics, network, Wi-Fi, sound,
storage, USB) and USB parts (camera, Bluetooth, sound, storage). Names come from hwdata's free lists.
"""
import os

from . import HWDATA, SHARE, SYS, read

# PCI class (first 4 hex digits) -> what it is
PCI_KINDS = {"0300": "graphics", "0302": "graphics", "0380": "graphics", "0200": "network", "0280": "wifi",
             "0403": "sound", "0c03": "usb", "0101": "storage", "0104": "storage", "0106": "storage",
             "0107": "storage", "0108": "storage"}
USB_KINDS = {"0e": "camera", "e0": "bluetooth", "01": "sound", "08": "storage"}
WORDS = {"graphics": "Graphics card", "network": "Wired network", "wifi": "Wi-Fi", "sound": "Sound",
         "usb": "USB ports", "storage": "Drive controller", "camera": "Camera", "bluetooth": "Bluetooth"}


def driver(path):
    link = os.path.join(path, "driver")
    return os.path.basename(os.readlink(link)) if os.path.islink(link) else ""


def hexid(text):
    return text.strip().lower().replace("0x", "")[-4:] if text else ""


def pci():
    """[{'key', 'bus', 'kind', 'vendor', 'device', 'driver'}] for important PCI parts."""
    found = []
    base = os.path.join(SYS, "bus", "pci", "devices")
    for slot in sorted(os.listdir(base)) if os.path.isdir(base) else []:
        path = os.path.join(base, slot)
        cls = read(os.path.join(path, "class")).lower().replace("0x", "")
        kind = PCI_KINDS.get(cls[:4])
        if not kind:
            continue
        ven, dev = hexid(read(os.path.join(path, "vendor"))), hexid(read(os.path.join(path, "device")))
        found.append({"key": "pci:%s:%s:%s" % (slot, ven, dev), "bus": "pci", "kind": kind,
                      "vendor": ven, "device": dev, "driver": driver(path)})
    return found


def usb():
    """Important USB parts, one per (maker, model, kind); it has a driver if any of its parts has one."""
    found = {}
    base = os.path.join(SYS, "bus", "usb", "devices")
    for name in sorted(os.listdir(base)) if os.path.isdir(base) else []:
        if ":" not in name:
            continue
        path = os.path.join(base, name)
        kind = USB_KINDS.get(read(os.path.join(path, "bInterfaceClass")).lower())
        if not kind:
            continue
        parent = os.path.join(base, name.split(":")[0])
        ven, dev = hexid(read(os.path.join(parent, "idVendor"))), hexid(read(os.path.join(parent, "idProduct")))
        key = "usb:%s:%s:%s" % (ven, dev, kind)
        item = found.setdefault(key, {"key": key, "bus": "usb", "kind": kind, "vendor": ven,
                                      "device": dev, "driver": ""})
        item["driver"] = item["driver"] or driver(path)
    return list(found.values())


def scan():
    return pci() + usb()


def names(items):
    """Add 'name' to each item: 'NVIDIA Corporation AD103M [GeForce RTX 5090 Laptop GPU]' when known."""
    want = {}
    for it in items:
        want.setdefault(it["bus"], set()).add((it["vendor"], it["device"]))
    found = {}
    for bus, pairs in want.items():
        vendors = {v for v, _ in pairs}
        ven = ""
        text = read(os.path.join(HWDATA, "%s.ids" % bus))
        for line in text.splitlines():
            if not line or line[0] == "#":
                continue
            if line[0] != "\t":
                if line[:4].isalnum() and len(line) > 6 and line[4:6] == "  ":
                    ven = line[:4].lower() if line[:4].lower() in vendors else ""
                    if ven:
                        found[(bus, ven, "")] = line[6:].strip()
                else:
                    ven = ""
            elif ven and not line.startswith("\t\t") and line[5:7] == "  ":
                dev = line[1:5].lower()
                if (ven, dev) in pairs:
                    found[(bus, ven, dev)] = line[7:].strip()
    for it in items:
        maker = found.get((it["bus"], it["vendor"], ""), "maker %s" % it["vendor"])
        model = found.get((it["bus"], it["vendor"], it["device"]), "model %s" % it["device"])
        it["name"] = "%s %s" % (maker, model)
    return items


def advice(item):
    """Plain advice for a part with no driver: from known-devices.txt, else a general tip."""
    want = "%s:%s:%s" % (item["bus"], item["vendor"], item["device"])
    for line in read(os.path.join(SHARE, "known-devices.txt")).splitlines():
        key, _, tip = line.partition(" ~ ")
        if key.strip().lower() == want and tip.strip():
            return tip.strip()
    tips = {"wifi": "This Wi-Fi chip has no Linux driver. A USB Wi-Fi adapter that says 'Linux' on the box works right away.",
            "bluetooth": "This Bluetooth part has no driver. A small USB Bluetooth adapter works right away.",
            "camera": "This camera has no driver. Most USB webcams that say 'UVC' work right away.",
            "graphics": "The graphics card has no driver, so the screen is slow. Ask Forge Helper or your helper.",
            "sound": "This sound part has no driver. USB headsets and speakers work right away."}
    return tips.get(item["kind"], "This part has no driver. Ask Forge Helper or your family helper.")


def missing(items):
    """Parts with no driver (the yellow "!"), with names."""
    return names([it for it in items if not it["driver"]])


def lost(before, now):
    """Parts that HAD a driver in the last good version and have none now (or are gone)."""
    now_by = {it["key"]: it for it in now}
    found = []
    for it in before:
        if not it.get("driver"):
            continue
        cur = now_by.get(it["key"])
        if it["bus"] == "pci" and (cur is None or not cur["driver"]):
            found.append(dict(it, driver=""))
        elif it["bus"] == "usb" and cur is not None and not cur["driver"]:
            found.append(dict(it, driver=""))
    return names(found)
