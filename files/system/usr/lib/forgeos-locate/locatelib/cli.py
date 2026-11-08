"""forgeos-locate commands. Exit: 0 fine, 1 not set up / could not, 3 wrong use or not allowed."""
import sys

USAGE = """usage: forgeos-locate status | report | serial (root)
  watch [--once]        (root: the forgeos-locate service)
  alert-watch [--once]  (your session: ring, message, lock the password safe)
  root setup [--photo] | root link | root photo on|off | root off   (root: through forgeos-locate-root)"""


def serial():
    from .setup import serial_number
    print(serial_number())
    return 0 if serial_number() != "-" else 1


def main(argv):
    from . import is_root
    cmd, rest = (argv[0], argv[1:]) if argv else ("", [])
    if cmd == "status" and not rest:
        from . import report
        return report.status()
    if cmd == "report" and not rest:
        from . import report
        return report.report()
    if cmd == "serial" and not rest:
        return serial()
    if cmd == "watch" and rest in ([], ["--once"]):
        if not is_root():
            print("Only the Find My PC service (root) runs the watcher.", file=sys.stderr)
            return 3
        from . import watch
        return watch.main(bool(rest))
    if cmd == "alert-watch" and rest in ([], ["--once"]):
        from . import alert
        return alert.main(bool(rest))
    if cmd == "root" and rest:
        if not is_root():
            print("This needs the PC password (forgeos-locate-root through pkexec).", file=sys.stderr)
            return 3
        from . import setup
        code = setup.main(rest)
        if code != 3:
            return code
    print(USAGE, file=sys.stderr)
    return 3
