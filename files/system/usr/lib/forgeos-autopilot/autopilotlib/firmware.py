"""BIOS and device firmware through fwupd and the free LVFS (signed updates from the PC makers).

Signed LVFS firmware needs no password (fwupd's own polkit rules); anything else does, on purpose.
BIOS updates are only made ready here; the PC's firmware writes them at the next restart.
"""
from . import run, run_json

FW = "fwupdmgr"
SLOW = 1800


def flags(obj):
    found = obj.get("Flags") or []
    return set(found if isinstance(found, list) else [found])


def is_bios(dev):
    """The system firmware (BIOS / UEFI): an internal device updated with a UEFI capsule."""
    protos = dev.get("Protocols") or [dev.get("Protocol") or ""]
    capsule = any("org.uefi.capsule" in str(p) for p in protos) or dev.get("Plugin") == "uefi_capsule"
    return capsule and "internal" in flags(dev)


def trusted(rel):
    marks = flags(rel) | set(rel.get("TrustFlags") or [])
    return bool(marks & {"trusted-metadata", "trusted-payload"}) and rel.get("RemoteId") != "lvfs-testing"


def devices():
    """Every device fwupd knows: [dict] (empty if fwupd is not running)."""
    code, data = run_json([FW, "get-devices", "--json"], 120)
    found = data.get("Devices") if isinstance(data, dict) else None
    return [d for d in found if isinstance(d, dict)] if isinstance(found, list) else []


def item(dev, rel=None):
    rel = rel or {}
    probs = dev.get("Problems") or []
    return {"id": str(dev.get("DeviceId") or ""), "name": str(dev.get("Name") or "a device"),
            "vendor": str(dev.get("Vendor") or ""), "now": str(dev.get("Version") or "?"),
            "new": str(rel.get("Version") or ""), "summary": str(rel.get("Summary") or ""),
            "urgency": str(rel.get("Urgency") or ""), "bios": is_bios(dev),
            "reboot": bool(flags(dev) & {"needs-reboot", "needs-shutdown"}) or is_bios(dev),
            "problems": [str(p) for p in probs] if isinstance(probs, list) else [str(probs)],
            "minutes": max(1, int(rel.get("InstallDuration") or 0) // 60) if rel.get("InstallDuration") else 0}


def updates():
    """Signed updates waiting: [item] - one per device, the newest trusted upgrade. None = could not check."""
    code, data = run_json([FW, "get-updates", "--json"], 300)
    if code == 2 or (code == 0 and data is None):
        return []
    found = data.get("Devices") if isinstance(data, dict) else None
    if not isinstance(found, list):
        return None if code not in (0, 2) else []
    out = []
    for dev in found:
        rels = [r for r in dev.get("Releases") or [] if isinstance(r, dict) and trusted(r)
                and "is-downgrade" not in flags(r)]
        if dev.get("DeviceId") and rels:
            out.append(item(dev, rels[0]))
    return out


def system_firmware():
    """The BIOS as fwupd sees it: item (updatable or not), or None if fwupd can't see it at all."""
    for dev in devices():
        if is_bios(dev):
            it = item(dev)
            it["updatable"] = "updatable" in flags(dev)
            return it
    return None


def install(dev_id):
    """Install (devices) or make ready for the next restart (BIOS). True if fwupd says it worked."""
    return run([FW, "update", dev_id, "--assume-yes", "--no-reboot-check"], SLOW)[0] == 0


def result(dev_id):
    """(state, version, error) of the last update of one device: state success/failed/pending/needs-reboot/''."""
    code, data = run_json([FW, "get-results", dev_id, "--json"], 60)
    if code != 0 or not isinstance(data, dict):
        return "", "", ""
    if isinstance(data.get("Devices"), list) and data["Devices"]:
        data = data["Devices"][0]
    rel = (data.get("Releases") or [{}])[0] if isinstance(data.get("Releases"), list) else {}
    return (str(data.get("UpdateState") or ""), str(rel.get("Version") or data.get("Version") or ""),
            str(data.get("UpdateError") or ""))
