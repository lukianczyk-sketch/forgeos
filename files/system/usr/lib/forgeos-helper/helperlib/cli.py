"""forgeos-helper commands. Output: plain lines for people, then TAB-separated lines for the window:
  TOOL<TAB>tool<TAB>how            the tool that answered (how: rules, ai or guess)
  ACTION<TAB>action<TAB>arg<TAB>button label     a change the user can say Yes to
Exit: 0 OK, 1 did not work / nothing found, 2 not allowed, 3 wrong use.
"""
import os
import sys

from . import actions, ai, clean, helpdocs, memory, read_json, router, selftest, state_dir, talk, watch
from .looks import LOOK

USAGE = """Usage: forgeos-helper ask [--no-ai] QUESTION...   (or - to read the question from input)
       forgeos-helper run ACTION [ARG] --yes
       forgeos-helper remember TEXT | memory | forget --yes
       forgeos-helper feedback up|down TOOL QUESTION...
       forgeos-helper selftest [--no-ai] [--quick] [--model MODEL]
       forgeos-helper models | brains | watch-tick | warm | tools | help-search WORDS..."""


def usage():
    print(USAGE, file=sys.stderr)
    return 3


def answer(question, use_ai=True):
    """(text, tool, how, actions) for one question. Never changes anything."""
    r = router.route(question, use_ai)
    tool, arg = r["tool"], r["arg"]
    if tool == "remember":
        return memory.remember(arg), tool, r["how"], []
    if tool == "memory_show":
        return memory.show(), tool, r["how"], []
    if tool == "forget_all":
        return ("I can forget everything you asked me to remember."), tool, r["how"], [("forget_all", "", "Forget everything")]
    if tool == "help_answer" and not helpdocs.best(arg, 1):
        tool = "just_answer"
    if tool == "help_answer":
        text, acts = talk.help_answer(arg, use_ai)
    elif tool == "just_answer":
        text, acts = talk.just_answer(arg, use_ai)
    else:
        text, acts, _level = LOOK[tool](arg)
    return text, tool, r["how"], acts


def cmd_ask(args):
    use_ai = "--no-ai" not in args
    q = " ".join(a for a in args if a != "--no-ai").strip()
    if q == "-":
        q = sys.stdin.read(4000).strip()
    q = clean(q, 4000)
    if not q:
        return usage()
    text, tool, how, acts = answer(q, use_ai)
    print(text)
    print("TOOL\t%s\t%s" % (tool, how))
    for a in acts:
        if actions.check_action(a[0], a[1]) is None:
            print("ACTION\t%s\t%s\t%s" % (a[0], a[1], a[2]))
    return 0


def cmd_run(args):
    if "--yes" not in args:
        print("Changes need the user's Yes: add --yes (the Forge Helper window asks first).", file=sys.stderr)
        return 3
    rest = [a for a in args if a != "--yes"]
    if not 1 <= len(rest) <= 2:
        return usage()
    code, msg = actions.do(rest[0], rest[1] if len(rest) > 1 else "")
    print(msg)
    return code


def cmd_brains():
    """Which brains the helper uses; QUICKGET when the small fast brain is worth downloading."""
    names = ai.downloaded()
    main, quick = ai.main_model(names), ai.quick_model(names)
    print("MAIN\t%s" % (main or "-"))
    print("QUICK\t%s" % (quick or "-"))
    if main and ai.QUICK_DEFAULT not in names and quick == main:
        size = next((c[1] for c in selftest.candidates() if c[0] == ai.QUICK_DEFAULT), "")
        print("QUICKGET\t%s\t%s" % (ai.QUICK_DEFAULT, size))
    found = read_json(os.path.join(state_dir(), "helper-models.json"), {})
    for name, size in (found.get("_suggest") or []) if isinstance(found, dict) else []:
        if name not in names:
            print("SUGGEST\t%s\t%s" % (name, size))
    return 0


def main(argv):
    if not argv:
        return usage()
    cmd, args = argv[0], argv[1:]
    if cmd == "ask":
        return cmd_ask(args)
    if cmd == "run":
        return cmd_run(args)
    if cmd == "remember" and args:
        print(memory.remember(" ".join(args)))
        return 0
    if cmd == "memory" and not args:
        print(memory.show())
        return 0
    if cmd == "forget" and args == ["--yes"]:
        print(actions.do("forget_all", "")[1])
        return 0
    if cmd == "feedback" and len(args) >= 3 and args[0] in ("up", "down"):
        memory.feedback(args[0], args[1], " ".join(args[2:]))
        print("Thank you. " + ("I'll try to do better." if args[0] == "down" else "Glad it helped."))
        return 0
    if cmd == "selftest":
        if "--model" in args:
            i = args.index("--model")
            if i + 1 >= len(args):
                return usage()
            os.environ["FORGEOS_HELPER_MODEL"] = args[i + 1]
        pct, good, total = selftest.score("--no-ai" not in args, "--quick" in args)
        print("Score: %.1f%% (%d of %d right)" % (pct, good, total))
        print("SCORE\t%.1f\t%d\t%d" % (pct, good, total))
        return 0 if total else 1
    if cmd == "models" and not args:
        return selftest.models()
    if cmd == "brains" and not args:
        return cmd_brains()
    if cmd == "watch-tick" and not args:
        return watch.tick()
    if cmd == "warm" and not args:
        return 0 if ai.warm(ai.quick_model()) else 1
    if cmd == "tools" and not args:
        for k, v in router.TOOLS.items():
            print("%s\t%s" % (k, v))
        return 0
    if cmd == "help-search" and args:
        for s, c in helpdocs.best(" ".join(args)):
            print("%d\t%s\t%s" % (s, c["name"], c["title"]))
        return 0
    return usage()
