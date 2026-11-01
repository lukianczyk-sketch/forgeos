"""The built-in help library: short fact cards in /usr/share/forgeos/helper/help/*.md.

Card format:  line 1 "# Title", line 2 "words: other words people use", then the facts.
A simple word score picks the best cards; the AI may only answer from those cards.
"""
import os
import re

from . import SHARE

WORD = re.compile(r"[a-z0-9]+")
STOP = set("""a an the my me i we our is are was were be of for to in on at by with and or not do does
did how can could would should will what where when which who why it its this that these those
there here please help want need get got have has had you your from into up out about just like
some any all thing things something anything way use using make sure computer pc forgeos add
new fix tell know show see give""".split())


def stem(w):
    for end in ("ing", "ers", "ies", "ed", "es", "er", "s"):
        if len(w) > len(end) + 2 and w.endswith(end):
            return w[:-len(end)] + ("y" if end == "ies" else "")
    return w


def words(text, raw=False):
    found = [w for w in WORD.findall(text.lower()) if w not in STOP]
    return found if raw else [stem(w) for w in found]


def load():
    """All cards: [{'name', 'title', 'words', 'body'}], sorted by file name."""
    folder = os.path.join(SHARE, "help")
    cards = []
    try:
        names = sorted(n for n in os.listdir(folder) if n.endswith(".md"))
    except OSError:
        return cards
    for n in names:
        try:
            with open(os.path.join(folder, n), encoding="utf-8") as f:
                lines = f.read().splitlines()
        except OSError:
            continue
        if len(lines) < 3 or not lines[0].startswith("# ") or not lines[1].startswith("words:"):
            continue
        cards.append({"name": n[:-3], "title": lines[0][2:].strip(), "words": lines[1][6:].strip(),
                      "body": "\n".join(lines[2:]).strip()})
    return cards


def score(card, qwords, qraw=()):
    """Title words count 3, the 'words:' line 2, the facts 1 (each question word once).
    The very same word (not just the same stem) in the title or 'words:' line counts 1 more."""
    title, extra, body = set(words(card["title"])), set(words(card["words"])), set(words(card["body"]))
    exact = set(words(card["title"] + " " + card["words"], raw=True))
    total, strong = len(exact & set(qraw)), 0
    for w in set(qwords):
        if w in title:
            total, strong = total + 3, strong + 1
        elif w in extra:
            total, strong = total + 2, strong + 1
        elif w in body:
            total += 1
    return total if strong else 0


def best(question, n=3, cards=None):
    """The N best cards for QUESTION as [(score, card)], best first; only cards that really match."""
    qwords = words(question)
    if not qwords:
        return []
    qraw = words(question, raw=True)
    found = [(score(c, qwords, qraw), c) for c in (load() if cards is None else cards)]
    found = [x for x in found if x[0] >= 2]
    found.sort(key=lambda x: (-x[0], x[1]["name"]))
    return found[:n]
