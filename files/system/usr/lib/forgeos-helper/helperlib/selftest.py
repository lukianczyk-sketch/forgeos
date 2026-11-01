"""Tested like a product: score the helper on hundreds of real questions, and keep the best model.

Test files: /usr/share/forgeos/helper/tests/*.jsonl, one case per line:
  {"q": "...", "tool": "scam_check" or ["a", "b"], "arg": "word the argument must hold", "card": "help card name" or [names]}
The user's thumbs-down questions ({"q", "not_tool"}) are added: the old wrong tool must not come back.
"""
import json
import os
import re
import time

from . import SHARE, ai, config_dir, helpdocs, read_json, read_lines, router, run, state_dir, write_json
from .memory import my_tests_file


def cases(quick=False):
    found = []
    folder = os.path.join(SHARE, "tests")
    try:
        names = sorted(n for n in os.listdir(folder) if n.endswith(".jsonl"))
    except OSError:
        names = []
    for n in names:
        for line in read_lines(os.path.join(folder, n)):
            try:
                found.append(json.loads(line))
            except ValueError:
                pass
    if quick:
        found = found[::5]
    for line in read_lines(my_tests_file()):
        try:
            found.append(json.loads(line))
        except ValueError:
            pass
    return [c for c in found if isinstance(c, dict) and c.get("q")]


def passes(case, use_ai):
    """(True/False, what the helper picked)."""
    r = router.route(case["q"], use_ai)
    want = case.get("tool")
    want = [want] if isinstance(want, str) else (want or [])
    ok = (not want or r["tool"] in want) and r["tool"] != case.get("not_tool")
    if ok and case.get("arg"):
        ok = case["arg"].lower() in r["arg"].lower()
    if ok and case.get("card") and r["tool"] == "help_answer":
        top = helpdocs.best(case["q"], 1)
        cards = case["card"] if isinstance(case["card"], list) else [case["card"]]
        ok = bool(top) and top[0][1]["name"] in cards
    return ok, "%s %s" % (r["tool"], r["arg"][:40] if r["tool"] in ("pc_fix", "text_bigger", "will_it_run") else "")


def score(use_ai=True, quick=False, show=print):
    todo = cases(quick)
    good = 0
    for c in todo:
        ok, got = passes(c, use_ai)
        good += ok
        if not ok:
            show("FAIL\t%s\twant %s\tgot %s" % (c["q"][:70], c.get("tool") or "not " + str(c.get("not_tool")), got.strip()))
    pct = 100.0 * good / len(todo) if todo else 0.0
    return pct, good, len(todo)


def vram_mb():
    code, out = run(["forgeos-ai-setup", "--dry-run"], 60)
    m = re.search(r"^VRAM: (\d+) MB", out, re.M) if code == 0 else None
    return int(m.group(1)) if m else 0


def candidates():
    """[(model, size, graphics GB)] from candidates.txt, best first."""
    out = []
    for line in read_lines(os.path.join(SHARE, "candidates.txt")):
        p = line.split()
        if not line.startswith("#") and len(p) >= 3:
            try:
                out.append((p[0], p[1], float(p[2])))
            except ValueError:
                pass
    return out


def suggestions(names):
    """At most one free model: the best one that fits this PC's graphics memory, only when it is
    better (higher on the list) than every model already downloaded."""
    vram = vram_mb()
    for name, size, gb in candidates():
        if name in names:
            return []
        if gb * 1000 <= vram:
            return [(name, size)]
    return []


def models(show=print):
    """Score every downloaded model; switch only to a model that scores HIGHER. Never downloads."""
    names = ai.downloaded()
    if not names:
        show("No AI models are downloaded. Open ForgeOS AI Setup to add one.")
        return 1
    path = os.path.join(state_dir(), "helper-models.json")
    scores = read_json(path, {})
    scores = scores if isinstance(scores, dict) else {}
    current = ai.main_model(names)
    for name in names:
        os.environ["FORGEOS_HELPER_MODEL"] = name
        pct, good, total = score(True, True, show=lambda *_: None)
        scores[name] = {"score": round(pct, 1), "when": time.strftime("%Y-%m-%d")}
        show("MODEL\t%s\t%.1f%%" % (name, pct))
    os.environ.pop("FORGEOS_HELPER_MODEL", None)
    best = max(names, key=lambda n: (scores[n]["score"], n == current))
    if best != current and scores[best]["score"] > scores.get(current, {}).get("score", -1):
        os.makedirs(config_dir(), exist_ok=True)
        with open(os.path.join(config_dir(), "helper-model"), "w", encoding="utf-8") as f:
            f.write(best + "\n")
        show("SWITCHED\t%s\t%s" % (current, best))
    else:
        show("KEPT\t%s" % current)
    found = suggestions(names)
    for name, size in found:
        show("SUGGEST\t%s\t%s" % (name, size))
    scores["_suggest"] = [list(x) for x in found]
    write_json(path, scores)
    return 0
