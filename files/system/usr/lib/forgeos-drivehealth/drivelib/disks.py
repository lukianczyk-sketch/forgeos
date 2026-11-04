"""Which drives to check, and reading each drive's own health report (smartctl, read-only).

Every internal drive (NVMe, SATA SSD, hard drive) is checked. A USB drive is checked when it is plugged in
and is 100 GB or bigger (a backup drive); small USB sticks have no health report, so they are left out.
"""
import hashlib
import re

from . import clean, run_json

SKIP = re.compile(r"^/dev/(loop|zram|ram|sr|fd|nbd|md|dm-)|^/dev/mmcblk\d+(boot\d|rpmb)$")
USB_SMALLEST = 100 * 10 ** 9


def drives():
    """[{dev, model, size, usb, rotating}] for every drive worth checking."""
    code, data = run_json(["lsblk", "-J", "-d", "-b", "-p", "-o", "PATH,TYPE,TRAN,MODEL,SIZE,RM,ROTA"], 30)
    found = []
    for d in (data or {}).get("blockdevices", []) if code == 0 else []:
        dev, size = d.get("path") or "", int(d.get("size") or 0)
        usb = d.get("tran") == "usb"
        if d.get("type") != "disk" or not dev or SKIP.search(dev) or size <= 0:
            continue
        if usb and size < USB_SMALLEST:
            continue
        found.append({"dev": dev, "model": clean(d.get("model") or "", 60), "size": size, "usb": usb,
                      "rotating": str(d.get("rota")).lower() in ("1", "true")})
    return found


def smart(d):
    """The drive's own health report as a dict (smartctl --json), or None when it can't be read."""
    cmd = ["smartctl", "-j", "-a"]
    if not d["dev"].startswith("/dev/nvme"):
        cmd += ["-l", "devstat"]
    if d["usb"]:
        cmd += ["-d", "sat"]
    code, data = run_json(cmd + [d["dev"]], 120)
    if not data or code & 3:  # bit 0 = bad command line, bit 1 = the drive could not be opened
        return None
    if "smart_status" not in data and "nvme_smart_health_information_log" not in data \
            and "ata_smart_attributes" not in data:
        return None
    return data


def key(d, data):
    """A short private name for the drive (made from its serial number, which is never saved)."""
    serial = (data or {}).get("serial_number") or ""
    raw = "%s|%s" % ((data or {}).get("model_name") or d["model"], serial or d["dev"])
    return hashlib.sha256(raw.encode()).hexdigest()[:12]
