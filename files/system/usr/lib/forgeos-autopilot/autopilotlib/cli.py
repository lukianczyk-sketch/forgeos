"""forgeos-autopilot commands. Exit: 0 all good / done, 1 something needs you / failed,
2 an update is waiting, 3 could not check / wrong use."""
import sys

from . import log_lines, save_settings, settings
from . import afterboot, devices, drivers, gpu, notes, report
from .commands import after_boot, bios_cmd, devices_cmd, drivers_cmd, firmware_cmd


def usage():
    print("usage: forgeos-autopilot status | check | drivers | devices [--all] | bios | image\n"
          "       forgeos-autopilot firmware list | firmware install ID|devices | firmware results\n"
          "       forgeos-autopilot after-boot | keep-version | go-back --yes | switch-image --yes\n"
          "       forgeos-autopilot fix-updates | enroll-key | restart | tick | set devices auto|ask | log [N]",
          file=sys.stderr)
    return 3


def main(args):
    cmd, rest = (args[0], args[1:]) if args else ("", [])
    simple = {"status": report.status, "check": report.check, "drivers": drivers_cmd, "bios": bios_cmd,
              "after-boot": after_boot}
    if cmd in simple and not rest:
        return simple[cmd]()
    if cmd == "devices" and rest in ([], ["--all"]):
        return devices_cmd(rest == ["--all"])
    if cmd == "image" and not rest:
        ref = drivers.image(drivers.deployments()[0])
        print("IMAGE\t%s\t%s\t%s" % (gpu.advice(devices.scan(), ref), ref or "-", gpu.other_image(ref) or "-"))
        return 0
    if cmd == "firmware":
        code = firmware_cmd(rest)
        return usage() if code == 3 and rest[:1] not in (["list"],) else code
    if cmd == "keep-version" and not rest:
        return 0 if afterboot.keep_version() else 1
    if cmd == "go-back" and rest == ["--yes"]:
        ok = afterboot.go_back()
        print("Done. Restart the PC to use the version from before the update." if ok else "Could not go back.")
        return 0 if ok else 1
    if cmd == "switch-image" and rest == ["--yes"]:
        ref = drivers.image(drivers.deployments()[0])
        ok = gpu.switch(ref)
        print("Done. Restart the PC to finish switching." if ok else "Could not switch (nothing was changed).")
        return 0 if ok else 1
    if cmd == "fix-updates" and not rest:
        ok = drivers.fix_updater()
        print("Automatic updates are on again." if ok else "Could not switch automatic updates on.")
        return 0 if ok else 1
    if cmd == "enroll-key" and not rest:
        return 0 if gpu.enroll_key() else 1
    if cmd == "restart" and not rest:
        return 0 if notes.restart() else 1
    if cmd == "tick" and not rest:
        from . import tick
        return tick.main()
    if cmd == "set" and len(rest) == 2 and rest[0] == "devices" and rest[1] in ("auto", "ask"):
        found = settings()
        found["devices"] = rest[1]
        save_settings(found)
        print("Device firmware: %s." % ("installs by itself" if rest[1] == "auto" else "asks you first"))
        return 0
    if cmd == "log" and len(rest) <= 1 and all(x.isdigit() for x in rest):
        for line in log_lines(int(rest[0]) if rest else 20):
            print("\t".join(line))
        return 0
    return usage()
