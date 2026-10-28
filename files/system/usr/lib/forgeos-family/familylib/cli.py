"""Family Mode on / off / status / text size, and the desktop icons."""
import os

from . import APPS, SIZES, forget_saved, load_saved, run, store_saved
from . import call, guards, helper, look, rustdesk

# Desktop icons: (menu entry, name on the desktop)
ICONS = [("forgeos-callhelp.desktop", "Call for help"), ("forgeos-scamshield.desktop", "Is this a scam?"),
         ("forgeos-askpc.desktop", "Ask Your PC")]
MARK = "X-ForgeOS-Family=true"


def usage():
    print("usage: forgeos-family on [--size big|bigger] | off | status | size big|bigger | guards\n"
          "       forgeos-family helper set --name NAME [--phone NUMBER] [--rustdesk-id ID] [--me YOUR-NAME]\n"
          "       forgeos-family helper show | helper clear\n"
          "       forgeos-family call | text ID | call-end")
    return 3


def desktop_dir():
    code, out = run(["xdg-user-dir", "DESKTOP"], timeout=5)
    path = out.strip() if code == 0 else ""
    return path if path.startswith("/") else os.path.join(os.path.expanduser("~"), "Desktop")


def ours(path):
    try:
        with open(path) as f:
            return MARK in f.read().splitlines()
    except OSError:
        return False


def add_icons():
    where = desktop_dir()
    os.makedirs(where, exist_ok=True)
    made = 0
    for name, title in ICONS:
        try:
            with open(os.path.join(APPS, name)) as f:
                lines = f.read().splitlines()
        except OSError:
            continue
        lines = ["Name=" + title if l.startswith("Name=") else l for l in lines]
        lines.insert(lines.index("[Desktop Entry]") + 1 if "[Desktop Entry]" in lines else 0, MARK)
        path = os.path.join(where, "forgeos-family-" + name)
        if os.path.exists(path) and not ours(path):
            made += 1  # a file of your own with this name: left alone
            continue
        with open(path, "w") as f:
            f.write("\n".join(lines) + "\n")
        os.chmod(path, 0o755)  # Plasma only starts desktop icons that may run
        made += 1
    return made == len(ICONS)


def remove_icons():
    where = desktop_dir()
    for name, _ in ICONS:
        path = os.path.join(where, "forgeos-family-" + name)
        if ours(path):
            os.remove(path)  # only ever our own icons


def show_guards(found):
    for state, text in found:
        print("  %s: %s" % (guards.WORDS[state], text))


def on(size):
    saved = load_saved()
    size = size or saved.get("size") or "big"
    if "look" not in saved:
        saved["look"] = look.capture()
        store_saved(saved)  # written down BEFORE anything changes, so "off" can always put it back
    problems = look.apply(saved["look"], size)
    if not rustdesk.lock(saved, helper.load().get("rustdesk_id", "")):
        problems.append("RustDesk could not be locked down (is its settings file broken?).")
    if not add_icons():
        problems.append("Some desktop icons could not be made.")
    saved.update(on=True, size=size)
    store_saved(saved)
    print("Family Mode is ON. Text size: %s." % size.capitalize())
    print("Safety guards:")
    show_guards(guards.check(turn_on=True))
    print("Call for help: RustDesk only lets someone in after you click Accept.")
    if not helper.load():
        print("Set up your helper so Call for help knows who to ask.")
    for p in problems:
        print("Problem: " + p)
    return 1 if problems else 0


def off():
    saved = load_saved()
    if not saved:
        print("Family Mode is already off.")
        return 0
    problems = look.restore(saved["look"]) if "look" in saved else []
    call.end(quiet=True)
    if not rustdesk.unlock(saved):
        problems.append("RustDesk's old settings could not be put back.")
    remove_icons()
    if problems:
        saved["on"] = False
        store_saved(saved)  # keep the old settings, so turning it off again can finish the job
        for p in problems:
            print("Problem: " + p)
        return 1
    forget_saved()
    print("Family Mode is OFF. Text, mouse pointer, taskbar and RustDesk are back the way they were.")
    print("The safety guards stay on - they keep you safe either way.")
    return 0


def resize(size):
    saved = load_saved()
    if not saved.get("on"):
        print("Family Mode is off. Turn it on first.")
        return 1
    problems = look.apply(saved["look"], size)
    saved["size"] = size
    store_saved(saved)
    print("Text size is now %s." % size.capitalize())
    for p in problems:
        print("Problem: " + p)
    return 1 if problems else 0


def status():
    saved, who = load_saved(), helper.load()
    opts = rustdesk.options(rustdesk.read_text()) or {}
    locked = all(opts.get(k) == v for k, v in rustdesk.LOCK.items())
    print("STATUS\t" + ("on" if saved.get("on") else "off"))
    print("SIZE\t" + (saved.get("size") or "-"))
    print("HELPER\t" + (who.get("name") or "-"))
    print("RUSTDESK\t" + ("locked" if locked else "open"))
    for state, text in guards.check(turn_on=False):
        print("GUARD\t%s\t%s" % (state, text))
    return 0


def size_arg(rest):
    if "--size" in rest:
        i = rest.index("--size")
        value = rest[i + 1] if i + 1 < len(rest) else ""
        return value if value in SIZES else None
    return ""
