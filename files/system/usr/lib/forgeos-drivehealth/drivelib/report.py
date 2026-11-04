"""What the last check found: lines for the window (status) and plain words for people (report)."""
import time

from . import LEVELS, REPORT, load_json
from . import backup

HOURS_A_YEAR = 8766
WORDS = {"good": "Good", "watch": "WATCH - early signs", "danger": "DANGER - this drive may be failing",
         "unknown": "can't read its health"}


def load():
    r = load_json(REPORT)
    return r if isinstance(r.get("drives"), list) and r.get("checked") else None


def code(r):
    return LEVELS.index(r["level"]) if r and r.get("level") in LEVELS else 3


def dash(x):
    return "-" if x is None else str(x)


def years(d):
    """Years of use, as people say it: 2, 1.5 (None when the drive doesn't say)."""
    return None if d.get("hours") is None else "%g" % round(d["hours"] / HOURS_A_YEAR, 1)


def status():
    r, b = load(), backup.status()
    if r:
        print("CHECKED\t%d\t%s" % (int(r["checked"]), r["level"]))
        for d in r["drives"]:
            print("\t".join(["DRIVE", d["key"], d["level"], d["name"], d["kind"], d["size"], dash(d.get("worn")),
                             dash(years(d)), dash(d.get("temp")), d["dev"], "yes" if d.get("usb") else "no"]))
            for why in d.get("reasons", []):
                print("REASON\t%s\t%s" % (d["key"], why))
    else:
        print("CHECKED\tnever\t-")
    print("BACKUP\tnone" if not b["set"] else "BACKUP\tset\t%s" % dash(b["days"]))
    return code(r)


def details(d):
    bits = []
    if d.get("worn") is not None:
        bits.append("about %d%% worn out" % d["worn"])
    if years(d) is not None:
        bits.append("%s years of use" % years(d))
    if d.get("temp") is not None:
        bits.append("%d degrees C" % d["temp"])
    text = ", ".join(bits)
    return (" " + text[:1].upper() + text[1:] + ".") if bits and d["level"] != "unknown" else ""


def report():
    r, b = load(), backup.status()
    if not r:
        print("Drive Health has not checked your drives yet. It checks 10 minutes after start-up, then every day.")
        print(backup.words(b))
        return 3
    print("Drive Health - last checked %s." % time.strftime("%A %d %B at %H:%M", time.localtime(r["checked"])))
    if r["level"] == "danger":
        print("A drive may be failing. Back up your files today, while they can still be read.")
    for d in r["drives"]:
        print("%s (%s, %s): %s.%s" % (d["name"], d["kind"], d["size"], WORDS.get(d["level"], d["level"]), details(d)))
        for why in d.get("reasons", []):
            print("  - " + why)
    if not r["drives"]:
        print("No drives with a health report were found.")
    print(backup.words(b))
    if r["level"] == "good":
        print("Some drives die with no warning at all, so keep your backup fresh.")
    return code(r)
