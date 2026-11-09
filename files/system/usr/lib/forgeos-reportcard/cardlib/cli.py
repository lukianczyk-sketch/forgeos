"""forgeos-reportcard commands. Exit: 0 all A or B, 1 something C or lower (or nothing checked), 3 wrong use."""
import os
import sys
import time

from . import HOME, now, run
from . import grade, keep, pdf


def usage():
    print("usage: forgeos-reportcard check | report | json | history | monthly | save [FILE]", file=sys.stderr)
    return 3


def history():
    cards = keep.load()
    if not cards:
        print("No report cards saved yet. The first one is made 10 minutes after the PC starts.")
    for x in reversed(cards):
        moon = time.strftime("%B %Y", time.strptime(x["month"], "%Y-%m"))
        print("%s: %s%s" % (moon, x["grade"], "" if x.get("points") is None else " (%s points)" % x["points"]))
    return 0


def main(args):
    cmd, rest = (args[0], args[1:]) if args else ("", [])
    if cmd in ("check", "report", "json") and not rest:
        c = grade.card()
        ch = keep.change(c)
        print("\n".join(grade.lines(c, ch)) if cmd == "check" else grade.words(c, ch) if cmd == "report"
              else grade.as_json(c, ch))
        return 0 if grade.is_good(c) else 1
    if cmd == "history" and not rest:
        return history()
    if cmd == "monthly" and not rest:
        return keep.monthly(grade.card)
    if cmd == "save" and len(rest) <= 1:
        c = grade.card()
        name = "PC-Report-Card-%s.pdf" % time.strftime("%Y-%m-%d", time.localtime(now()))
        docs = run(["xdg-user-dir", "DOCUMENTS"], 10)[1].strip()
        docs = docs if docs.startswith("/") and docs.rstrip("/") != HOME else os.path.join(HOME, "Documents")
        print(pdf.write(c, keep.change(c), rest[0] if rest else os.path.join(docs, name)))
        return 0
    return usage()
