"""The code cards to print and hand over: the whole opening code, or Half A and Half B for the two-key
lock. Written only to the in-memory work space, opened in the browser for printing, then deleted."""
import os

from . import SCRATCH, esc, full_name, nice_day, write_private
from .pages import page
from .words import halves

CARDS = os.path.join(SCRATCH, "code-cards.html")


def cards(code, two, holders, made):
    """The code cards to print and hand over (never saved on the drive)."""
    who = full_name()
    parts = list(zip(("Half A", "Half B"), halves(code))) if two else [("Opening code", code)]
    b = "<h1>Code cards</h1><p>Print this page, cut out the card(s) and give them away. ForgeOS does not keep the code.</p>"
    for i, (label, words) in enumerate(parts):
        name = holders[i][1] if i < len(holders) else ""
        b += ('<div class="card"><h2>%s - %s\'s Emergency Envelope</h2><p>Made %s. For: <b>%s</b></p>'
              '<p class="code">%s</p><p>Keep this card safe. %s</p></div>'
              % (esc(label), esc(who), esc(nice_day(made)), esc(name), esc(words),
                 "The other half is with someone else. You need both." if two else "Only use it if something happens to me."))
    return page("Code cards", b)


def write(code, two, holders, made):
    os.makedirs(SCRATCH, mode=0o700, exist_ok=True)
    write_private(CARDS, cards(code, two, holders, made))
    return CARDS


def forget():
    """Delete the printed code cards page (the window does this once you printed them)."""
    if os.path.lexists(CARDS):
        os.unlink(CARDS)
