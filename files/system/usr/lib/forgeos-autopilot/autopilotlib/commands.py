"""The longer forgeos-autopilot commands: drivers, devices, bios, firmware, after-boot."""
from . import log_lines, save_state, state
from . import afterboot, devices, drivers, firmware, safety


def drivers_cmd():
    booted, pending = drivers.deployments()
    if booted is None:
        print("Could not read the system version (rpm-ostree).")
        return 3
    if pending:
        rows, fixes = drivers.changes(str(booted.get("checksum")), str(pending.get("checksum")))
        print("New drivers are ready: %s." % (drivers.describe(rows or [], fixes) or "fixes and improvements"))
        print("They switch on the next time you restart.")
    last = state().get("last_change")
    if last:
        print("Last change (%s): %s." % (last.get("date", "?"), last.get("text", "?")))
    for name, version in sorted(drivers.installed().items()):
        print("DRIVER\t%s\t%s" % (name, version))
    return 2 if pending else 0


def devices_cmd(show_all):
    items = devices.names(devices.scan())
    for it in items:
        word = devices.WORDS.get(it["kind"], it["kind"])
        if it["driver"]:
            if show_all:
                print("OK\t%s\t%s\t%s" % (word, it["name"], it["driver"]))
        else:
            print("MISSING\t%s\t%s\t%s:%s:%s\t%s" % (word, it["name"], it["bus"], it["vendor"], it["device"], devices.advice(it)))
    return 1 if any(not it["driver"] for it in items) else 0


def bios_cmd():
    d = safety.dmi()
    sf = firmware.system_firmware()
    age = safety.bios_age_days(d["date"])
    maker, page = safety.maker_page(d["maker"])
    print("BIOS\t%s\t%s\t%s\t%s" % (d["maker"] or "-", d["model"] or "-", d["version"] or "-", d["date"] or "-"))
    print("AGE\t%s" % (age if age is not None else "-"))
    print("WAY\t%s" % ("lvfs" if sf and sf.get("updatable") else ("watch" if sf else "unknown")))
    print("PAGE\t%s\t%s" % (maker or "-", page or "-"))
    print("USBTOOL\t%s" % (safety.usb_tool(d["maker"]) or "-"))
    print("TPM\t%s" % ("yes" if safety.tpm_unlock() else "no"))
    for why in safety.bios_blockers():
        print("BLOCKED\t%s" % why)
    return 0


def firmware_cmd(rest):
    if rest == ["list"]:
        ups = firmware.updates()
        if ups is None:
            print("Could not check for firmware updates right now.")
            return 3
        for u in ups:
            print("\t".join(["UPDATE", u["id"], u["name"], u["now"], u["new"], "bios" if u["bios"] else "device",
                             ",".join(u["problems"]) or "-", u["summary"] or "-"]))
        if not ups:
            print("All firmware is up to date.")
        return 2 if ups else 0
    if len(rest) == 2 and rest[0] == "install":
        ups = firmware.updates() or []
        pick = [u for u in ups if not u["bios"]] if rest[1] == "devices" else [u for u in ups if u["id"] == rest[1]]
        if not pick:
            print("No update is waiting for that.")
            return 1
        from .tick import stage_bios
        st, worst = state(), 0
        for u in pick:
            if u["bios"]:
                msg = stage_bios(st, u)
                ok = msg.startswith("Ready")
            else:
                ok = firmware.install(u["id"])
                msg = "%s is up to date." % u["name"] if ok else "%s was not changed (the update failed)." % u["name"]
            print(msg)
            worst = worst if ok else 1
        save_state(st)
        return worst
    if rest == ["results"]:
        staged = state().get("bios_staged")
        if staged:
            print("BIOS %s is ready and installs at the next restart." % staged.get("version", "?"))
        for when, kind, text in log_lines(50):
            if kind in ("bios", "firmware"):
                print("%s\t%s" % (when, text))
        return 0
    return 3


def after_boot():
    ab = afterboot.check()
    if ab["state"] == "problem":
        print("PROBLEM\t" + " ".join(p["text"] for p in ab["problems"]))
        return 1
    print("OK\t%s\t%s" % (ab["state"], drivers.describe(ab["changes"])))
    return 0
