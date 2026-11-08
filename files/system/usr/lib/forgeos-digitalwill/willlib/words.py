"""The codes: plain short English words, picked at random by the PC's secure random-number maker.

The opening code is 10 words (about 103 bits - nobody can guess it). With the two-key lock it is two
halves of 5 words: one half alone leaves 5 unknown words, far too many to try. The PC unlock code (typed
when the PC starts) is 8 words. Words come from the EFF Short Wordlist (1,295 words).
"""
import os
import re
import secrets

from . import CODE_WORDS, KEY_WORDS, SHARE

_CACHE = []


def wordlist():
    if not _CACHE:
        words = []
        for part in ("words-1.txt", "words-2.txt"):
            try:
                with open(os.path.join(SHARE, part), encoding="utf-8") as f:
                    for line in f:
                        if not line.startswith("#"):
                            words.extend(line.split())
            except OSError:
                pass
        _CACHE.extend(sorted(set(w for w in words if re.fullmatch(r"[a-z]{3,9}", w))))
    return _CACHE


def ok():
    """The word list is all there (1,295 words)."""
    return len(wordlist()) == 1295


def pick(n):
    words = wordlist()
    if len(words) < 1000:
        raise RuntimeError("the word list is missing")
    return " ".join(secrets.choice(words) for _ in range(n))


def opening_code():
    return pick(CODE_WORDS)


def unlock_code():
    return pick(KEY_WORDS)


def halves(code):
    """Half A and Half B of an opening code (5 words each)."""
    w = code.split()
    mid = len(w) // 2
    return " ".join(w[:mid]), " ".join(w[mid:])


def tidy(typed):
    """What someone typed, made plain: small letters, one space between words (dashes, commas, dots
    and new lines count as spaces), so "Acid-Acorn,  ACRE" opens the same as "acid acorn acre"."""
    return " ".join(re.split(r"[\s,.;:_/-]+", typed.strip().lower())).strip()
