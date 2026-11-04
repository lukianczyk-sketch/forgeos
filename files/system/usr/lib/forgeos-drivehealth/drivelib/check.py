"""The daily check (root): reads every drive, judges it, saves the report everyone can read and the history.

Report: /var/lib/forgeos-drivehealth/report.json (0644, no serial numbers). History: history.json (0600).
"""
from . import HISTORY, REPORT, is_root, load_json, now, save_json, size_words
from . import btrfs, disks, judge, selftest, smart

KEEP = 120  # history rows per drive (four months of daily checks)


def check_all(timer=False):
    """Check every drive. Returns the report dict (or None when not run as root)."""
    if not is_root():
        return None
    t = now()
    hist = load_json(HISTORY)
    rows_by = hist.setdefault("drives", {})
    fs_errors = btrfs.errors()
    found = []
    for d in disks.drives():
        data = disks.smart(d)
        k = disks.key(d, data)
        base = {"key": k, "dev": d["dev"], "usb": d["usb"], "size": size_words(d["size"]), "read": bool(data)}
        if not data:
            found.append(dict(base, name=d["model"] or "Drive", kind="USB drive" if d["usb"] else "drive",
                              level="unknown", worn=None, hours=None, temp=None, bad=0,
                              reasons=["Can't read this drive's health (some USB boxes hide it)."]))
            continue
        f = smart.facts(d, data)
        fs = fs_errors.get(d["dev"], {})
        rows = rows_by.get(k, [])
        level, reasons = judge.judge(f, fs, rows, t)
        found.append(dict(base, name=f["name"], kind=f["kind"], level=level, reasons=reasons, worn=f["worn"],
                          hours=f["hours"], temp=f["temp"], bad=f["bad"]))
        rows.append({"t": t, "bad": f["bad"], "worn": f["worn"], "fs": fs.get("errors", 0)})
        rows_by[k] = rows[-KEEP:]
    old = load_json(REPORT)
    level = judge.overall(found)
    since = old.get("danger_since", 0) if level == "danger" and old.get("level") == "danger" else 0
    report = {"version": 1, "checked": t, "level": level, "drives": found,
              "danger_since": since or (t if level == "danger" else 0)}
    if timer:
        report["selftest"] = selftest.maybe_start(found, hist, t)
    save_json(HISTORY, hist, 0o600)
    save_json(REPORT, report, 0o644)
    return report
