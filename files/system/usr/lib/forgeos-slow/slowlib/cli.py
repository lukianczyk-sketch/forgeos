"""forgeos-slow commands. Exit: 0 nothing slowing the PC, 1 something found, 3 wrong use."""
import sys

from . import history, judge, space, startup


def usage():
    print("usage: forgeos-slow check | report | earlier [MINUTES] | quick | sample\n"
          "       forgeos-slow space | startup | fix NAME [ARGS]   (the window uses these)", file=sys.stderr)
    return 3


def main(args):
    cmd, rest = (args[0], args[1:]) if args else ("", [])
    if cmd in ("check", "report") and rest in ([], ["--no-internet"]):
        probs, oks = judge.run_all(internet=not rest)
        if cmd == "check":
            print("\n".join(judge.lines(probs, oks)))
        else:
            print(judge.words(probs, oks, "" if probs else "Earlier: " + history.then(30)))
        return 1 if probs else 0
    if cmd == "earlier" and (not rest or (len(rest) == 1 and rest[0].isdigit() and 0 < int(rest[0]) <= 10080)):
        print(history.then(int(rest[0]) if rest else 30))
        return 0
    if cmd == "quick" and not rest:
        from . import game_on
        slow, text = history.quick()
        if slow and not game_on():
            print(text)
            return 1
        return 0
    if cmd == "sample" and not rest:
        history.sample()
        return 0
    if cmd == "space" and not rest:
        print("\n".join(space.listing()))
        return 0
    if cmd == "startup" and not rest:
        for e in startup.entries():
            print("APP\t%s\t%s\t%s" % (e["id"], e["name"], "on" if e["on"] else "off"))
        return 0
    if cmd == "fix" and rest:
        from .fixes import fix
        code, text = fix(rest)
        print(text)
        return code
    return usage()
