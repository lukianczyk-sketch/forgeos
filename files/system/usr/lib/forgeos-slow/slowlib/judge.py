"""Runs every check and puts the findings in order: red first, then yellow, in the order of the checks."""
from . import checks, hot, more, net, procs

ORDER = ("hidden", "busy", "memory", "disk", "drive", "heat", "power", "background", "startup", "internet", "restart")


def run_all(internet=True):
    apps = procs.apps(procs.table())
    found = (more.hidden(apps) + checks.busy(apps) + checks.memory(apps) + checks.disk() + checks.drive()
             + hot.heat() + hot.power() + more.background(apps) + more.startup()
             + (net.internet() if internet else []) + more.restart())
    probs = [f for f in found if f[0] == "problem"]
    probs.sort(key=lambda f: (f[2] != "red", ORDER.index(f[1])))
    return probs, [f for f in found if f[0] == "ok"]


def lines(probs, oks):
    """TAB lines for the window: PROBLEM id level text fix button / OK id text."""
    out = ["PROBLEM\t%s\t%s\t%s\t%s\t%s" % f[1:] for f in probs]
    return out + ["OK\t%s\t%s" % f[1:] for f in oks]


def words(probs, oks, earlier=""):
    """The plain-English answer (Forge Helper shows this)."""
    if not probs:
        text = "Your PC looks fine right now - nothing is slowing it down."
        if earlier:
            text += "\n" + earlier
        return text + "\nChecked: " + " ".join(f[2] for f in oks)
    n = len(probs)
    out = ["Why Is It Slow? found %s:" % ("1 thing slowing your PC" if n == 1 else "%d things slowing your PC" % n)]
    for i, f in enumerate(probs, 1):
        out.append("%d. %s%s" % (i, "(important) " if f[2] == "red" else "", f[3]))
        if f[4] != "-":
            out.append("   Fix: \"%s\" in the Why Is It Slow? window." % f[5])
    return "\n".join(out)
