"""Safety checks before a BIOS update is made ready, and BIOS Watch for makers that don't use the LVFS.

A BIOS update must never lose power. ForgeOS checks the charger and battery itself (on top of fwupd's
own checks) and warns when the disk is unlocked by the TPM chip (a BIOS update changes what it measures).
"""
import os
import time

from . import ETC, SHARE, SYS, read, run

BATTERY_MIN = 50
OLD_DAYS = 365


def power():
    """(on the charger or a desktop, lowest battery % or None)."""
    base = os.path.join(SYS, "class", "power_supply")
    mains, batteries = None, []
    for name in sorted(os.listdir(base)) if os.path.isdir(base) else []:
        kind = read(os.path.join(base, name, "type"))
        if kind in ("Mains", "USB", "USB_PD", "USB_C"):
            mains = mains or read(os.path.join(base, name, "online")) == "1"
        elif kind == "Battery" and read(os.path.join(base, name, "scope")) != "Device":
            cap = read(os.path.join(base, name, "capacity"))
            if cap.isdigit():
                batteries.append(int(cap))
    if not batteries:
        return True, None
    return bool(mains), min(batteries)


def virtual():
    code, out = run(["systemd-detect-virt", "--vm"], 10)
    return code == 0 and out.strip() not in ("", "none")


def tpm_unlock():
    """True if the disk is unlocked by the TPM chip (systemd-cryptenroll) instead of only a password."""
    return "tpm2-device" in read(os.path.join(ETC, "crypttab"))


def bios_blockers():
    """Reasons a BIOS update can't be made ready right now ([] = safe to go ahead)."""
    found = []
    plugged, battery = power()
    if virtual():
        found.append("This is a virtual machine - BIOS updates are only for real PCs.")
    if not plugged:
        found.append("Plug in the charger first.")
    if battery is not None and battery < BATTERY_MIN:
        found.append("Let the battery charge to at least %d%% first (now %d%%)." % (BATTERY_MIN, battery))
    return found


def dmi():
    """{'maker', 'model', 'version', 'date'} of this PC's BIOS (from /sys/class/dmi/id)."""
    get = lambda n: read(os.path.join(SYS, "class", "dmi", "id", n))  # noqa: E731
    return {"maker": get("sys_vendor") or get("board_vendor"), "model": get("product_name") or get("board_name"),
            "version": get("bios_version"), "date": get("bios_date")}


def bios_age_days(date_text, now=None):
    """Days since the BIOS date 'MM/DD/YYYY' (None if unknown)."""
    try:
        made = time.mktime(time.strptime(date_text.strip(), "%m/%d/%Y"))
    except (ValueError, OverflowError):
        return None
    return int(((now or time.time()) - made) // 86400)


def month_year(date_text):
    try:
        return time.strftime("%B %Y", time.strptime(date_text.strip(), "%m/%d/%Y"))
    except ValueError:
        return date_text or "an unknown date"


def maker_page(maker):
    """(maker name, its BIOS download page) from makers.txt, or ('', '')."""
    low = maker.lower()
    for line in read(os.path.join(SHARE, "makers.txt")).splitlines():
        parts = [p.strip() for p in line.split(" ~ ")]
        if len(parts) == 3 and not line.startswith("#") and parts[0].lower() in low:
            return parts[1], parts[2]
    return "", ""


def usb_tool(maker):
    """The BIOS's own 'update from a USB stick' tool for this maker ('' = none known)."""
    tools = {"asus": "EZ Flash", "micro-star": "M-Flash", "msi": "M-Flash", "gigabyte": "Q-Flash",
             "asrock": "Instant Flash"}
    low = maker.lower()
    return next((v for k, v in tools.items() if k in low), "")
