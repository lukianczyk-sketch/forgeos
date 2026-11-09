"""Subjects 3, 6 and 7: drive health and backups (one Drive Health answer) and the Undo safety net."""
import re

from . import age, days_ago, one, rows, run, subject


def drive_and_backup():
    d = rows(run(["forgeos-drivehealth", "status"], 60)[1])
    names = lambda lvl: ", ".join(p[2] for p in d.get("DRIVE", []) if len(p) > 2 and p[1] == lvl)  # noqa: E731
    when, level = one(d, "CHECKED"), one(d, "CHECKED", 1)
    if not when:
        drive = subject("drive", "Drive health", None, "Drive Health did not answer.", "drivehealth")
    elif when == "never" or level == "unknown" or not any(len(p) > 1 and p[1] != "unknown" for p in d.get("DRIVE", [])):
        drive = subject("drive", "Drive health", None, "Drive Health has not read the drives' health yet.", "drivehealth")
    else:
        old = days_ago(int(when)) if when.isdigit() else 0
        late = (" (last checked %d days ago)" % old) if old > 30 else ""
        pts, why = {"good": (100, "All drives are healthy"), "watch": (72, "Early signs of wear: %s. Back up now" % names("watch")),
                    "danger": (40, "This drive may be failing: %s. Back up today" % names("danger"))}.get(level, (None, "?"))
        drive = subject("drive", "Drive health", None if pts is None else pts - (10 if late else 0), why + late + ".", "drivehealth")
    b = (d.get("BACKUP") or [[]])[0]
    if not b:
        back = subject("backup", "Backups", None, "Drive Health did not answer.", "drivehealth")
    elif b[0] == "none":
        back = subject("backup", "Backups", 50, "No backup is set up. A drive can die without any warning.", "drivehealth")
    elif not b[1:] or not b[1].isdigit():
        back = subject("backup", "Backups", 65, "A backup is set up, but it has not run yet.", "drivehealth")
    else:
        n = int(b[1])
        when = "today" if n == 0 else "yesterday" if n == 1 else "%d days ago" % n
        pts, more = (100, "") if n <= 7 else (88, "") if n <= 14 else (75, " That is getting old.") if n <= 30 else (55, " Make a fresh one.")
        back = subject("backup", "Backups", pts, "Your last backup was %s.%s" % (when, more), "drivehealth")
    return drive, back


def undo():
    code, out = run(["forgeos-undo", "status"], 60)
    if code == 1:
        return subject("undo", "Undo safety net", 45, "The Undo Button is off - deleted or changed files can't come back.", "undo")
    m, n = re.search(r"to (\d{4}-\d\d-\d\d)[\d: ]*$", out.strip()), re.search(r"(\d+) snapshots", out)
    if code != 0 or not out.strip():
        return subject("undo", "Undo safety net", None, "The Undo Button did not answer.", "undo")
    if not n or int(n.group(1)) == 0:
        return subject("undo", "Undo safety net", 75, "The Undo Button is on, but it has no snapshots yet.", "undo")
    if not m or age(m.group(1)) is None:
        return subject("undo", "Undo safety net", 90, "%s snapshots kept." % n.group(1), "undo")
    days = max(0, age(m.group(1)))
    pts = 100 if days <= 2 else 80 if days <= 7 else 60
    when = "today" if days == 0 else "yesterday" if days == 1 else "%d days ago" % days
    return subject("undo", "Undo safety net", pts, "%s snapshots kept; the newest is from %s." % (n.group(1), when), "undo")
