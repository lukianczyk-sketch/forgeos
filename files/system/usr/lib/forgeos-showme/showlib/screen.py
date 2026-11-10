"""Read the words that are really on the screen, and where they are.

A quiet screenshot (Spectacle: no window, no notification) is read with Tesseract (TSV = every word with its
box) and deleted at once. Places are given as parts of the screen (0 to 1), so they fit any screen size and
scale. Nothing is kept and nothing leaves the PC.
"""
import difflib
import os

from . import clean, norm, run, runtime

MIN_CONF = 20     # Tesseract's sureness (0-100); below this a "word" is usually a smudge
MIN_MATCH = 0.84  # how close an OCR line must be ("Add Prlnter" still counts as "Add Printer")


def shot():
    """Take a quiet screenshot of the whole desktop; return its path or None."""
    path = os.path.join(runtime(), "screen.png")
    try:
        os.unlink(path)
    except OSError:
        pass
    code, _ = run(["spectacle", "-b", "-n", "-f", "-o", path], 20)
    return path if code == 0 and os.path.isfile(path) else None


def parse(tsv):
    """Tesseract TSV -> (width, height, lines); a line = {"text", "words": [(text, left, top, w, h)]}."""
    width = height = 0
    lines = {}
    for row in tsv.splitlines()[1:]:
        c = row.split("\t")
        if len(c) < 12 or not c[0].isdigit():
            continue
        try:
            level, box, conf = int(c[0]), [int(x) for x in c[6:10]], float(c[10])
        except ValueError:
            continue
        if level == 1:
            width, height = box[2], box[3]
        elif level == 5 and conf >= MIN_CONF and c[11].strip():
            lines.setdefault(tuple(c[1:5]), []).append((c[11].strip(), box[0], box[1], box[2], box[3]))
    out = [{"text": " ".join(w[0] for w in ws), "words": ws} for ws in lines.values()]
    return width, height, out


def read(path):
    """(width, height, lines) of a picture, or None when Tesseract could not read it."""
    code, out = run(["tesseract", path, "-", "--psm", "11", "tsv"], 30)
    if code != 0:
        return None
    w, h, lines = parse(out)
    return (w, h, lines) if w > 0 and h > 0 else None


def look():
    """Screenshot + read + delete: (width, height, lines), or None when the screen could not be read."""
    path = shot()
    if not path:
        return None
    try:
        return read(path)
    finally:
        try:
            os.unlink(path)
        except OSError:
            pass


def look_alike(text):
    """Letters OCR often mixes up made the same ("Caneel" = "Cancel", "Fi1e" = "File", "rn" = "m")."""
    return text.replace("rn", "m").translate(str.maketrans("c1l0", "eiio"))


def inside(x, y, rects):
    return any(r[0] <= x <= r[0] + r[2] and r[1] <= y <= r[1] + r[3] for r in rects)


def find_all(screen, phrase, avoid=(), ours=""):
    """Every place PHRASE is on the screen, best first, as (x, y, w, h) parts of the screen (0 to 1).
    Exact before nearly, a whole line before part of one. Skipped: matches inside AVOID (our own label and
    step panel, as parts of the screen) and longer lines that are our own words (OURS = what we show)."""
    if not screen:
        return []
    width, height, lines = screen
    want = norm(phrase)
    n = len(want.split())
    found = []
    for line in lines:
        ws = [w for w in line["words"] if norm(w[0])]
        if ours and len(ws) > n and " ".join(norm(w[0]) for w in ws) in ours:
            continue
        for i in range(0, max(0, len(ws) - n) + 1):
            part = ws[i:i + n]
            got = " ".join(norm(w[0]) for w in part)
            score = 1.0 if got == want else 0.99 if look_alike(got) == look_alike(want) else \
                difflib.SequenceMatcher(None, got, want).ratio()
            if score < (0.99 if len(want) <= 4 else MIN_MATCH):
                continue
            left, top = min(w[1] for w in part), min(w[2] for w in part)
            right, bottom = max(w[1] + w[3] for w in part), max(w[2] + w[4] for w in part)
            box = (left / width, top / height, (right - left) / width, (bottom - top) / height)
            if not inside(box[0] + box[2] / 2, box[1] + box[3] / 2, avoid):
                found.append(((score, len(ws) == n), box))
    found.sort(key=lambda x: x[0], reverse=True)
    return [box for _, box in found]


def find(screen, phrase, avoid=(), ours=""):
    """The best place PHRASE is on the screen, or None (see find_all)."""
    got = find_all(screen, phrase, avoid, ours)
    return got[0] if got else None


def visible(screen, most=120):
    """The lines of words on the screen, for the AI to choose from (it may only pick one of these)."""
    seen, out = set(), []
    for line in (screen[2] if screen else []):
        text = clean(line["text"], 40)
        if len(norm(text)) >= 2 and text.lower() not in seen:
            seen.add(text.lower())
            out.append(text)
    return out[:most]
