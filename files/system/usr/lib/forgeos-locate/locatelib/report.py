"""What the window and Forge Helper show. Reads only the no-secrets status file (anyone may read it)."""
from . import STATUS, load_json, run, when


def facts():
    s = load_json(STATUS)
    code, out = run(["systemctl", "is-active", "forgeos-locate.service"], 10)
    s["service"] = "running" if code == 0 and out.strip() == "active" else "stopped"
    return s


def status():
    """TAB lines for the window. Exit 0 set up, 1 not set up."""
    s = facts()
    t = lambda k: when(s[k]) if s.get(k) else "-"  # noqa: E731
    print("SETUP\t" + ("yes" if s.get("setup") else "no"))
    print("MADE\t" + t("made"))
    print("LOST\t%s\t%s" % ("yes" if s.get("lost") else "no", t("lost")))
    print("PHOTO\t" + ("on" if s.get("photo") else "off"))
    print("HEARD\t%s\t%s" % (t("heard"), s.get("last_cmd") or "-"))
    print("HEARDAT\t%d" % int(s.get("heard", 0)))
    print("CHECKED\t" + t("checked"))
    print("REPORTS\t%d\t%s" % (int(s.get("reports", 0)), t("last_report")))
    print("SERVICE\t" + s["service"])
    return 0 if s.get("setup") else 1


def report():
    """Plain English (Forge Helper). Exit 0 set up, 1 not set up."""
    s = facts()
    if not s.get("setup"):
        print("Find My PC is not set up yet. Open Find My PC and click \"Set up Find My PC\" - it takes 2 minutes "
              "and needs your phone. Then, if this PC is ever lost or stolen, your phone can see where it is, "
              "ring it and lock it. No company account, nothing is tracked on normal days.")
        return 1
    lines = ["Find My PC is set up (since %s)." % when(s["made"])]
    if s.get("lost"):
        lines.append("This PC is marked LOST since %s. It reports where it is to your phone. Reports sent: %d."
                     % (when(s["lost"]), int(s.get("reports", 0))))
    else:
        lines.append("Normal: it only looks for a message from your phone and sends nothing.")
    if s.get("checked"):
        lines.append("Last reached the relay: %s." % when(s["checked"]))
    if s.get("heard"):
        lines.append("Last heard your phone: %s (%s)." % (when(s["heard"]), s.get("last_cmd") or "-"))
    lines.append("Webcam photo while lost: %s." % ("on" if s.get("photo") else "off"))
    if s["service"] != "running":
        lines.append("WARNING: the Find My PC service is not running - restart the PC.")
    if not s.get("lost"):
        lines.append("If this PC is stolen: open your Find My PC page on your phone and tap \"Mark as lost\". "
                     "Also tell the police and give them the serial number.")
    print("\n".join(lines))
    return 0
