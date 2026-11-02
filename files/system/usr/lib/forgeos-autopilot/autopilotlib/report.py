"""Everything at once: tab lines for the window (status) and a plain report for people (check)."""
from . import settings, state
from . import afterboot, devices, drivers, firmware, gpu, safety


def gather():
    """One look at everything (read-only, except remembering the last good version)."""
    ab = afterboot.check()
    now = ab["now"]
    ups = firmware.updates()
    sf = firmware.system_firmware()
    info = safety.dmi()
    pending = []
    fixes = 0
    if now["pending"]:
        pending, fixes = drivers.changes(now["checksum"], now["pending"])
    return {"ab": ab, "now": now, "ups": ups, "sf": sf, "dmi": info, "pending": pending, "fixes": fixes,
            "updater": drivers.updater(), "missing": devices.missing(now["devices"]),
            "image": gpu.advice(now["devices"], now["image"]),
            "nvidia": gpu.nvidia_problem(now["devices"], now["image"]) or "ok",
            "age": safety.bios_age_days(info["date"]), "blockers": safety.bios_blockers()}


def bios_way(g):
    if g["sf"] is None:
        return "unknown"
    return "lvfs" if g["sf"].get("updatable") else "watch"


def status():
    g = gather()
    ups = g["ups"] or []
    bios = next((u for u in ups if u["bios"]), None)
    last = state().get("last_change") or {}
    print("DRIVERS\t%s\t%s" % ("waiting" if g["now"]["pending"] else "current",
                               drivers.describe(g["pending"] or [], g["fixes"]) if g["now"]["pending"] else last.get("text", "")))
    print("UPDATES\t%s" % g["updater"])
    print("FIRMWARE\t%d\t%s\t%s" % (len([u for u in ups if not u["bios"]]), bios["new"] if bios else "-",
                                    "checked" if g["ups"] is not None else "not-checked"))
    d = g["dmi"]
    print("BIOS\t%s\t%s\t%s\t%s\t%s" % (d["maker"] or "-", d["model"] or "-", d["version"] or "-", d["date"] or "-", bios_way(g)))
    print("DEVICES\t%d" % len(g["missing"]))
    print("IMAGE\t%s" % g["image"])
    print("NVIDIA\t%s" % g["nvidia"])
    print("AFTERBOOT\t%s\t%s" % (g["ab"]["state"], " ".join(p["text"] for p in g["ab"]["problems"])))
    print("SETTING\tdevices\t%s" % settings()["devices"])
    return 0


def check():
    """Plain report. Exit 0 all good, 1 something needs you, 2 an update is waiting for a restart or a Yes."""
    g = gather()
    need, wait, lines = False, False, []
    if g["ab"]["state"] == "problem":
        need = True
        lines.append("PROBLEM after the last update: " + " ".join(p["text"] for p in g["ab"]["problems"]) +
                     " Drivers & BIOS can go back to the version from before.")
    if g["now"]["pending"]:
        wait = True
        lines.append("New drivers are ready (%s). They switch on the next time you restart." %
                     (drivers.describe(g["pending"] or [], g["fixes"]) or "fixes and improvements"))
    else:
        lines.append("Drivers: up to date (they update by themselves with ForgeOS).")
    if g["updater"] != "ok":
        need = True
        lines.append("Automatic updates are %s. Drivers & BIOS can fix that." % ("switched off" if g["updater"] == "off" else "failing"))
    ups = g["ups"]
    if ups is None:
        lines.append("Firmware: could not check right now (no internet or fwupd not running).")
    for u in ups or []:
        wait = True
        lines.append("%s update ready for %s: %s to %s. %s" % ("BIOS" if u["bios"] else "Firmware", u["name"], u["now"], u["new"], u["summary"]))
    if ups == [] and bios_way(g) == "lvfs":
        lines.append("BIOS: up to date (version %s)." % (g["dmi"]["version"] or "?"))
    elif bios_way(g) != "lvfs":
        maker = safety.maker_page(g["dmi"]["maker"])[0] or g["dmi"]["maker"] or "Your PC maker"
        lines.append("BIOS: version %s from %s. %s doesn't send BIOS updates to ForgeOS by itself." %
                     (g["dmi"]["version"] or "?", safety.month_year(g["dmi"]["date"]), maker))
        if g["age"] is not None and g["age"] >= safety.OLD_DAYS:
            need = True
            lines.append("Your BIOS is over a year old - Drivers & BIOS shows how to update it.")
    for m in g["missing"]:
        need = True
        lines.append("No driver: %s (%s). %s" % (devices.WORDS.get(m["kind"], m["kind"]), m["name"], devices.advice(m)))
    if g["image"] in ("to-nvidia", "to-plain"):
        need = True
        lines.append("This PC would run better on the %s version of ForgeOS." % ("NVIDIA" if g["image"] == "to-nvidia" else "AMD/Intel"))
    elif g["image"] == "old-nvidia":
        lines.append("Graphics: this NVIDIA card is older than the NVIDIA version of ForgeOS supports, so this version is the right one.")
    if g["nvidia"] == "secure-boot":
        need = True
        lines.append("Secure Boot is blocking the NVIDIA driver. A one-time setup fixes it.")
    elif g["nvidia"] == "not-loaded":
        need = True
        lines.append("The NVIDIA graphics driver did not start.")
    if not g["missing"]:
        lines.append("Devices: every important part has a driver.")
    print("\n".join(lines))
    return 1 if need else (2 if wait else 0)
