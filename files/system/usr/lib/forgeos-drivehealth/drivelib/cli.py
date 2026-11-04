"""forgeos-drivehealth commands. Exit: 0 good, 1 early signs, 2 a drive may be failing, 3 could not check."""
import sys

from . import CHECKER, ENV, is_root, run
from . import report


def usage():
    print("usage: forgeos-drivehealth status | report | check | tick\n"
          "       forgeos-drivehealth system-check [--timer]   (root: the daily check)", file=sys.stderr)
    return 3


def check():
    """Check now. As a normal user this asks the root checker (no password for the person at the PC)."""
    if is_root():
        from .check import check_all
        check_all()
    else:
        code, _out = run([ENV("FORGEOS_DH_PKEXEC") or "pkexec", CHECKER], 600)
        if code != 0:
            print("Drive Health could not check the drives right now.")
            return 3
    return report.report()


def main(args):
    cmd, rest = (args[0], args[1:]) if args else ("", [])
    if cmd == "status" and not rest:
        return report.status()
    if cmd == "report" and not rest:
        return report.report()
    if cmd == "check" and not rest:
        return check()
    if cmd == "tick" and not rest:
        from . import tick
        return tick.main()
    if cmd == "system-check" and rest in ([], ["--timer"]):
        if not is_root():
            print("system-check must run as root (the daily timer does it).", file=sys.stderr)
            return 3
        from .check import check_all
        r = check_all(timer=bool(rest))
        print("Checked %d drive(s): %s." % (len(r["drives"]), r["level"]))
        return report.code(r)
    return usage()
