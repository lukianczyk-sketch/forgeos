"""ForgeOS Find Anything (Job 11): small helpers for search words, dates and snippets."""
import re
import time

WORD = re.compile(r"[^\W_]+")


def clean_words(words):
    """Letters and digits only, lower case, no repeats, max 8."""
    out = []
    for w in words:
        for part in WORD.findall(str(w).lower()):
            if (len(part) > 1 or part.isdigit()) and part not in out:
                out.append(part)
    return out[:8]


def day(text, end=False):
    """YYYY-MM-DD -> seconds (start of that day, or its last second)."""
    try:
        t = time.mktime(time.strptime(text, "%Y-%m-%d"))
    except (TypeError, ValueError, OverflowError):
        return None
    return t + 86399 if end else t


def snip(body, low, words):
    """About 100 letters around the first word found, the word in [brackets]."""
    for w in words:
        i = low.find(w)
        if i >= 0:
            a, b = max(0, i - 50), i + len(w)
            return "..." + body[a:i] + "[" + body[i:b] + "]" + body[b:b + 50] + "..."
    return body[:100]
