"""Good / Watch / Danger for one drive, with the reasons in plain English.

The history (one row per check) lets it say "getting worse" - the strongest warning sign there is.
"""
from . import DAY, worst

WEEK = 8 * DAY
FAST = 10      # this many new bad spots in a week = danger
MANY = 100     # this many bad spots in all = danger
WORN = 90      # percent worn = watch


def hot_limit(kind):
    return 55 if kind == "hard drive" else 75 if kind == "NVMe SSD" else 70


def since(rows, field, value, t):
    """How much `field` grew since the last check, and over the last week (None = nothing to compare)."""
    old = [r for r in rows if r.get("t", 0) < t and isinstance(r.get(field), int)]
    if not old:
        return 0, 0
    week = [r[field] for r in old if r["t"] >= t - WEEK] or [old[-1][field]]
    return max(value - old[-1][field], 0), max(value - min(week), 0)


def judge(f, fs, rows, t):
    """(level, [reasons]) for a drive's facts f, its file-system errors fs and its history rows."""
    danger, watch = [], []
    if f["failing"]:
        danger.append("The drive itself says it is failing%s." % (" (%s)" % f["attr_failed"] if f["attr_failed"] else ""))
    if f["selftest"]:
        danger.append("The drive failed its own self-test.")
    new, week = since(rows, "bad", f["bad"], t)
    if week >= FAST:
        danger.append("Bad spots on the drive are growing fast (%d new this week)." % week)
    elif f["bad"] >= MANY:
        danger.append("The drive has many bad spots (%d)." % f["bad"])
    elif new > 0:
        watch.append("Getting worse: %d new bad spot%s since the last check." % (new, "" if new == 1 else "s"))
    elif f["bad"] > 0:
        watch.append("The drive has %d bad spot%s. That is an early warning sign." % (f["bad"], "" if f["bad"] == 1 else "s"))
    if fs.get("unfixed", 0) > 0:
        danger.append("Some of your files on this drive were damaged and could not be repaired.")
    elif since(rows, "fs", fs.get("errors", 0), t)[1] > 0:
        watch.append("ForgeOS found a read error on this drive this week (it was handled).")
    if f["worn"] is not None and f["worn"] >= WORN:
        watch.append("The drive is about %d%% worn out." % f["worn"])
    if f["spare_low"]:
        watch.append("The drive's spare space is running low.")
    if f["hot"] or (f["temp"] is not None and f["temp"] >= hot_limit(f["kind"])):
        watch.append("The drive is running too hot (%s degrees C)." % (f["temp"] if f["temp"] is not None else "over the safe"))
    if f["attr_past"] and not danger:
        watch.append("The drive had a problem in the past (%s)." % f["attr_past"])
    if danger:
        return "danger", danger + watch
    return ("watch" if watch else "good"), watch


def overall(drives):
    return worst(d["level"] for d in drives)
