"""The quiet timer (2 minutes after login, then every 6 hours): installs device firmware by itself and
shows at most ONE note that needs you, most important first. Never while a game or video is playing
(except "something stopped working"). Never restarts the PC by itself.
A note can wait up to an hour for an answer, so what happens after the answer is saved into a fresh copy
of the saved state (the window may have changed it in the meantime).
"""
import time

from . import ENV, busy, log, read, save_state, settings, state
from . import afterboot, firmware, notes, safety

DAY = 86400


def boot_id():
    return ENV("FORGEOS_AP_BOOT_ID") or read("/proc/sys/kernel/random/boot_id") or "?"


def due(st, key, days):
    """True if the note `key` was not shown in the last `days` days (and marks it shown)."""
    now = time.time()
    if now - float(st.get("told", {}).get(key, 0)) < days * DAY:
        return False
    st.setdefault("told", {})[key] = now
    return True


def after_problem(st, ab):
    key = ab["now"]["checksum"] + boot_id()
    if st.get("problem_told") == key:
        return False
    st["problem_told"] = key
    save_state(st)
    text = ("After the last update: %s\n\nForgeOS can put back the version from before the update. "
            "Your files are not touched." % " ".join(p["text"] for p in ab["problems"]))
    pick = notes.ask("Something stopped working", text, [("back", "Go back"), ("keep", "Keep this version")], True)
    if pick == "back" and afterboot.go_back():
        notes.tell("Going back", "Done. Restart the PC to use the version from before the update.")
    elif pick == "keep":
        afterboot.keep_version()
    return True


def bios_result(st):
    staged = st.get("bios_staged")
    if not staged or staged.get("boot") == boot_id():
        return False
    result, version, error = firmware.result(staged["id"])
    st.pop("bios_staged", None)
    tries = st.setdefault("bios_tries", {})
    if result == "success":
        log("bios", "BIOS update worked (now %s)." % (version or staged["version"]))
        notes.tell("BIOS updated", "Your BIOS update worked (now %s)." % (version or staged["version"]))
    else:
        tries[staged["version"]] = tries.get(staged["version"], 0) + 1
        log("bios", "BIOS update did not finish (%s %s)." % (result or "unknown", error))
        notes.tell("BIOS update did not finish", "Nothing was changed. ForgeOS will try again next week."
                   if tries[staged["version"]] < 2 else "Nothing was changed. ForgeOS stopped trying - see Drivers & BIOS.")
    save_state(st)
    return False


def device_firmware(st, ups):
    """Install device firmware by itself (setting 'auto'); in 'ask' mode return the first one to ask about."""
    mode = settings()["devices"]
    tries = st.setdefault("fw_tries", {})
    for up in [u for u in ups if not u["bios"] and not u["reboot"] and not u["problems"]]:
        key = up["id"] + "@" + up["new"]
        if tries.get(key, 0) >= 2:
            continue
        if mode == "ask":
            return up
        notes.tell("Updating %s" % up["name"], up["summary"] or "A firmware update from %s." % (up["vendor"] or "its maker"))
        ok = firmware.install(up["id"])
        tries[key] = 0 if ok else tries.get(key, 0) + 1
        log("firmware", "%s %s to %s: %s" % (up["name"], up["now"], up["new"], "installed" if ok else "FAILED"))
        notes.tell("Done" if ok else "Firmware update failed", "%s is up to date." % up["name"] if ok else
                   "%s was not changed. ForgeOS will try once more later." % up["name"])
        save_state(st)
    return None


def stage_bios(st, up):
    """Make a BIOS update ready for the next restart. Returns a plain message."""
    stop = safety.bios_blockers()
    if stop:
        return "Not yet: " + " ".join(stop)
    if not firmware.install(up["id"]):
        st.setdefault("bios_tries", {})[up["new"]] = st.get("bios_tries", {}).get(up["new"], 0) + 1
        log("bios", "Could not make BIOS %s ready." % up["new"])
        return "The BIOS update could not be made ready. Nothing was changed."
    st["bios_staged"] = {"id": up["id"], "version": up["new"], "boot": boot_id(), "at": time.time()}
    log("bios", "BIOS %s to %s is ready; it installs at the next restart." % (up["now"], up["new"]))
    return ("Ready. It installs the next time you restart (about %d minutes). The screen may go black - "
            "don't turn the PC off and keep the charger in." % max(up["minutes"], 3))


def main():
    ab = afterboot.check()
    st = state()
    if ab["state"] == "problem" and after_problem(st, ab):
        return 1
    if busy():
        return 0
    bios_result(st)
    from . import notices
    notices.other_notes(st, ab, firmware.updates() or [])
    return 0
