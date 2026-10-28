"""Call for help: open RustDesk (locked down), find this PC's ID, text it to the helper, end the help.

The help ends by itself after 2 hours (a user timer), so RustDesk never stays open by mistake.
"""
import os
import time

from . import SELF, STATE_DIR, clean, load_saved, run, store_saved
from . import helper, rustdesk

END_UNIT = "forgeos-family-call-end"
WAIT = float(os.environ.get("FORGEOS_FAMILY_ID_WAIT", "30"))
STEP = float(os.environ.get("FORGEOS_FAMILY_STEP", "2"))
LOG = os.path.join(STATE_DIR, "calls.log")


def log(text):
    os.makedirs(STATE_DIR, mode=0o700, exist_ok=True)
    with open(LOG, "a") as f:
        f.write("%s %s\n" % (time.strftime("%Y-%m-%d %H:%M"), clean(text, 200)))


def online():
    code, out = run(["nmcli", "-t", "networking", "connectivity"], timeout=10)
    return code != 0 or out.strip() not in ("none", "")


def phone_device():
    """The id of a paired phone that is here right now (KDE Connect), or ''."""
    code, out = run(["kdeconnect-cli", "-a", "--id-only"], timeout=10)
    ids = [l.strip() for l in out.splitlines() if l.strip()] if code == 0 else []
    return ids[0] if ids else ""


def arm_end():
    """End the help by itself after 2 hours."""
    run(["systemctl", "--user", "stop", END_UNIT + ".timer"], timeout=10)
    run(["systemd-run", "--user", "--on-active=2h", "--unit=" + END_UNIT, "--collect",
         "--description=ForgeOS: end Call for help after 2 hours", SELF, "call-end"], timeout=15)


def call():
    """Prints HELPER / ID / TEXT lines for the window. Exit 0 ok, 1 no ID, 2 no helper, 4 offline."""
    who = helper.load()
    if not who:
        print("No helper is set up yet. Run: forgeos-family helper set --name NAME")
        return 2
    if not online():
        print("This PC is not on the internet, so your helper can't reach it.\n"
              "Check the Wi-Fi (or the Panic Button's All Clear), then try again.")
        return 4
    saved = load_saved()
    if not rustdesk.lock(saved, who.get("rustdesk_id", "")):
        print("RustDesk could not be made safe, so it was not opened.")
        return 1
    store_saved(saved)
    if not rustdesk.running() and not rustdesk.start():
        print("RustDesk could not be opened.")
        return 1
    rid, waited = "", 0.0
    while True:
        rid = rustdesk.get_id()
        if rid or waited >= WAIT:
            break
        time.sleep(STEP)
        waited += STEP or 1
    if not rid:
        print("RustDesk opened, but its ID did not show up. Look at the top of the RustDesk window for 'ID'.")
        log("call: no ID")
        return 1
    arm_end()
    log("call: helper %s, ID %s" % (who["name"], rid))
    print("HELPER\t" + who["name"])
    print("ID\t" + rid)
    if not who.get("phone"):
        print("TEXT\tno-phone")
    else:
        print("PHONE\t" + who["phone"])
        print("TEXT\t" + ("ready" if phone_device() else "no-device"))
    return 0


def text(rid):
    """Text the helper this PC's RustDesk ID through the phone paired with KDE Connect."""
    who = helper.load()
    device = phone_device()
    digits = "".join(c for c in rid if c.isdigit())
    if not who.get("phone") or not device or not 6 <= len(digits) <= 12:
        print("The text could not be sent: no helper number, no phone connected, or no ID.")
        return 1
    me = who.get("me") or "Your family member"
    msg = ("%s needs help with the computer. Open RustDesk and connect to ID %s. "
           "(Sent by ForgeOS Call for help.)" % (me, helper.nice_id(digits)))
    code, _ = run(["kdeconnect-cli", "-d", device, "--send-sms", msg, "--destination", who["phone"]], timeout=30)
    log("text to %s: %s" % (who["name"], "sent" if code == 0 else "failed"))
    if code != 0:
        print("The text could not be sent. Call %s and read the number out loud instead." % who["name"])
        return 1
    print("Text sent to %s." % who["name"])
    return 0


def end(quiet=False):
    """Close RustDesk and stop the 2-hour timer."""
    run(["systemctl", "--user", "stop", END_UNIT + ".timer"], timeout=10)
    closed = not rustdesk.running() or rustdesk.stop()
    log("call ended" + ("" if closed else " (RustDesk would not close)"))
    if not quiet:
        run(["notify-send", "--app-name=Family Mode", "--icon=help-contents", "Call for help",
             "The help is over. RustDesk is closed, so nobody can get in now." if closed
             else "RustDesk would not close. Restart the PC to be sure nobody can get in."], timeout=10)
        print("RustDesk is closed." if closed else "RustDesk would not close.")
    return 0 if closed else 1
