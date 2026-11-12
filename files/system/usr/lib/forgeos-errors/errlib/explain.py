"""From any error text to a plain-English card: the scam check first, then the built-in library, then the
private AI (explain only). A card answers: What happened? Is it serious? What do I do? (+ one Fix it).
"""
from . import LEVELS, RULE, clean
from . import ai, fixes, library, scam


def from_entry(e):
    card = {k: e[k] for k in ("id", "level", "title", "say", "do") if k in e}
    if e.get("fix"):
        card["fix"] = e["fix"]
    if e.get("show"):
        card["show"] = e["show"]
    return card


def explain(text, use_ai=True, entries=None):
    """The card for TEXT, or None when nothing understood it (no library match and no AI)."""
    text = clean(text, 4000)
    if len(text) < 3:
        return None
    if scam.is_fake(text):
        return scam.card(text)
    e = library.best(text, library.load() if entries is None else entries)
    if e:
        return from_entry(e)
    return ai.explain(text) if use_ai else None


def lines(card, key=""):
    """The card as plain lines (for people and Forge Helper) and TAB lines (for the window)."""
    out = ["%s" % card["title"],
           "What happened: %s" % card["say"],
           "Is it serious? %s" % LEVELS.get(card["level"], ""),
           "What to do: %s" % card["do"]]
    if card.get("ai"):
        out.append("(Explained by the private AI on this PC, not from the checked list.)")
    out.append(RULE)
    out.append("CARD\t%s\t%s\t%s" % (key or card["id"], card["level"], clean(card["title"], 80)))
    if card.get("fix") and fixes.ok(card["fix"]):
        out.append("FIX\t%s\t%s" % (card["fix"], fixes.label(card["fix"])))
    if card.get("show") and fixes.has_guide(card["show"]):
        out.append("SHOW\t%s" % card["show"])
    return out
