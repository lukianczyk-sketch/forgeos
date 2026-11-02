"""The notes that need you, most important first (the timer shows at most one per run)."""
import time

from . import save_state, state
from . import drivers, firmware, gpu, notes, safety, devices
from .tick import due, device_firmware, stage_bios


def bios_note(st, up):
    if st.get("bios_tries", {}).get(up["new"], 0) >= 2 or st.get("bios_staged") or safety.bios_blockers():
        return False
    if not due(st, "bios-" + up["new"], 7):
        return False
    save_state(st)
    text = ("A new BIOS for your PC is ready (%s to %s). %s\nIt installs the next time you restart and takes about "
            "%d minutes. The screen may go black - don't turn the PC off." % (up["now"], up["new"], up["summary"], max(up["minutes"], 3)))
    if safety.tpm_unlock():
        text += "\nAfter it, you may have to type your disk password once - keep it handy."
    if notes.ask("BIOS update ready", text, [("go", "Get it ready"), ("later", "Not now")]) == "go":
        fresh = state()
        msg = stage_bios(fresh, up)
        save_state(fresh)
        notes.tell("BIOS update", msg)
    return True


def drivers_note(st, ab):
    pending = ab["now"]["pending"]
    if not pending or st.get("pending_told") == pending or time.time() < float(st.get("later_until", 0)):
        return False
    rows, fixes = drivers.changes(ab["now"]["checksum"], pending)
    what = drivers.describe(rows or [], fixes) or "fixes and improvements"
    pick = notes.ask("New drivers are ready", "New: %s.\nThey switch on the next time you restart." % what,
                     [("restart", "Restart now"), ("later", "Later")])
    fresh = state()
    fresh["pending_told"] = pending if pick == "restart" else ""
    fresh["later_until"] = time.time() + 20 * 3600
    save_state(fresh)
    if pick == "restart" and not notes.restart():
        notes.tell("Restart", "Please save your work and restart from the menu.")
    return True


def other_notes(st, ab, ups):
    now = ab["now"]
    up = device_firmware(st, ups) if ups else None
    if up and due(st, "fw-" + up["id"] + up["new"], 3):
        save_state(st)
        if notes.ask("Firmware update", "%s: %s to %s. %s" % (up["name"], up["now"], up["new"], up["summary"]),
                     [("go", "Install"), ("later", "Not now")]) == "go":
            notes.tell(up["name"], "Updated." if firmware.install(up["id"]) else "The update failed; nothing was changed.")
        return True
    bios = next((u for u in ups or [] if u["bios"]), None)
    if bios and bios_note(st, bios):
        return True
    if drivers_note(st, ab):
        return True
    if drivers.updater() != "ok" and due(st, "updater", 3):
        save_state(st)
        if notes.ask("Automatic updates", "Automatic system and driver updates are not working. Fix it now?",
                     [("fix", "Fix it"), ("later", "Not now")]) == "fix":
            notes.tell("Automatic updates", "Fixed." if drivers.fix_updater() else "Could not fix it - ask your helper.")
        return True
    if gpu.nvidia_problem(now["devices"], now["image"]) == "secure-boot" and due(st, "secureboot", 1):
        save_state(st)
        if notes.ask("Graphics driver blocked", "Secure Boot is blocking the NVIDIA driver. A one-time setup fixes it.",
                     [("fix", "Set it up"), ("later", "Not now")], True) == "fix":
            gpu.enroll_key()
        return True
    advice = gpu.advice(now["devices"], now["image"])
    if advice in ("to-nvidia", "to-plain") and due(st, "image", 30):
        save_state(st)
        if notes.ask("Faster graphics", "This PC would run better on the %s version of ForgeOS." %
                     ("NVIDIA" if advice == "to-nvidia" else "AMD/Intel"), [("show", "Show me"), ("later", "Not now")]) == "show":
            notes.window("--image")
        return True
    new = [m for m in devices.missing(now["devices"]) if m["key"] not in st.get("missing_told", [])]
    if new:
        st["missing_told"] = st.get("missing_told", []) + [m["key"] for m in new]
        save_state(st)
        if notes.ask("A part has no driver", "%s: %s" % (new[0]["name"], devices.advice(new[0])),
                     [("show", "Device Check"), ("later", "OK")]) == "show":
            notes.window("--devices")
        return True
    return bios_watch(st)


def bios_watch(st):
    sf = firmware.system_firmware()
    if sf and sf.get("updatable"):
        return False
    info = safety.dmi()
    age = safety.bios_age_days(info["date"])
    if age is None or age < safety.OLD_DAYS or not due(st, "bioswatch", 182):
        return False
    save_state(st)
    maker = safety.maker_page(info["maker"])[0] or info["maker"] or "Your PC maker"
    if notes.ask("Old BIOS", "Your BIOS is from %s. %s doesn't send BIOS updates to ForgeOS by itself." %
                 (safety.month_year(info["date"]), maker), [("show", "Show me how"), ("later", "Not now")]) == "show":
        notes.window("--bios")
    return True
