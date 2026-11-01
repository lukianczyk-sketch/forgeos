"""Checks Forge Helper's test questions (Job 13c tests): 300 or more, every tool and help card is real.

Usage: python3 tests/helper-check-tests.py /usr/lib/forgeos-helper
"""
import json
import os
import sys

sys.path.insert(0, sys.argv[1])
from helperlib import SHARE, helpdocs  # noqa: E402
from helperlib.tools import TOOLS  # noqa: E402

ok = set(TOOLS) | {"remember", "memory_show", "forget_all"}
names = {c["name"] for c in helpdocs.load()}
n = 0
for f in sorted(os.listdir(os.path.join(SHARE, "tests"))):
    for line in open(os.path.join(SHARE, "tests", f), encoding="utf-8"):
        c = json.loads(line)
        n += 1
        tools = c["tool"] if isinstance(c["tool"], list) else [c["tool"]]
        cards = c.get("card") or []
        if not set(tools) <= ok or not set(cards if isinstance(cards, list) else [cards]) <= names:
            sys.exit("bad test question: %s" % line.strip())
if n < 300:
    sys.exit("only %d test questions" % n)
print("%d test questions OK" % n)
