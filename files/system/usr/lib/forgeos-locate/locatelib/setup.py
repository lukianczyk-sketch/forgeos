"""The root half of the window's buttons (through pkexec /usr/libexec/forgeos-locate-root, which always asks
for the PC password - so a thief who is signed in can never see the phone link or turn Find My PC off).
  setup [--photo]  a NEW key (an older phone link stops working), then the phone link
  link             the phone link again
  photo on|off     the webcam photo while lost
  off              Find My PC off: key, reports and lost mode gone
"""
from . import ENV, KEYFILE, STATE, TRAIL, commands, now, remove, run, save_json, settings
from .seal import new_key, phone_link, topic

SERVICE = "forgeos-locate.service"


def service(what):
    run(["systemctl", what, SERVICE], 60)


def serial_number():
    """The PC's serial number for a police report (only root may read it). "-" when there is none."""
    for f in (ENV("FORGEOS_LOC_SERIAL") or "/sys/class/dmi/id/product_serial", "/sys/class/dmi/id/board_serial"):
        try:
            with open(f) as h:
                s = h.read().strip()
        except OSError:
            continue
        if s and s.lower() not in ("to be filled by o.e.m.", "default string", "none", "0"):
            return s[:64].replace("\t", " ")
    return "-"


def show(k):
    print("LINK\t" + phone_link(settings()["page"], k["key"], settings()["relay"]))
    print("SERIAL\t" + serial_number())
    print("BELL\t%s/%s" % (settings()["relay"].rstrip("/"), topic(k["key"], "bell")))
    return 0


def setup(photo):
    service("stop")
    commands.end_lost(commands.state())
    t = now()
    k = {"key": new_key(), "made": t, "photo": bool(photo)}
    save_json(KEYFILE, k, 0o600)
    save_json(STATE, {"since": str(int(t)), "fast_until": t + 15 * 60}, 0o600)
    remove(TRAIL)
    commands.write_status()
    service("start")
    return show(k)


def link():
    k = commands.key_info()
    if not k:
        print("Find My PC is not set up yet.")
        return 1
    return show(k)


def photo(on):
    k = commands.key_info()
    if not k:
        print("Find My PC is not set up yet.")
        return 1
    k["photo"] = on
    save_json(KEYFILE, k, 0o600)
    commands.write_status()
    print("Webcam photo while lost: %s." % ("on" if on else "off"))
    return 0


def off():
    service("stop")
    commands.end_lost(commands.state())
    for f in (KEYFILE, STATE, TRAIL):
        remove(f)
    commands.write_status({})
    service("start")
    print("Find My PC is off. Your phone link no longer works.")
    return 0


def main(rest):
    if rest in (["setup"], ["setup", "--photo"]):
        return setup(len(rest) == 2)
    if rest == ["link"]:
        return link()
    if len(rest) == 2 and rest[0] == "photo" and rest[1] in ("on", "off"):
        return photo(rest[1] == "on")
    if rest == ["off"]:
        return off()
    return 3
