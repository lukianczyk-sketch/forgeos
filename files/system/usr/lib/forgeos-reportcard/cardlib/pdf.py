"""A one-page PDF of the report card, for printing or handing to a family helper.

Written by hand (plain PDF 1.4, the two fonts every PDF reader has), so nothing extra is needed.
It always fits on one page (spacing, then the small text, shrinks when the card is long).
"""
import os
import textwrap
import time

from . import now

PAGE_W, PAGE_H, LEFT = 612, 792, 54


def esc(text):
    text = text.encode("cp1252", "replace").decode("cp1252")  # the fonts' WinAnsi letters (- " ' too)
    return text.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")


def page(c, change):
    """The drawing commands: (font, size, text) lines from the top down."""
    out = [("F2", 22, "PC Report Card"), ("F1", 10, time.strftime("%B %d, %Y", time.localtime(now()))), ("F1", 6, "")]
    top = c["grade"] + " - " + c["words"] if c["points"] is not None else c["words"]
    out.append(("F2", 26, "Overall: " + top))
    out += [("F1", 11, t) for t in textwrap.wrap(c["why"], 88)] + [("F1", 8, "")]
    for s in c["subjects"]:
        g = s["grade"] if s["points"] is not None else ("not checked yet" if s["grade"] else "not graded")
        out.append(("F2", 12, "%s   %s" % (g, s["name"])))
        out += [("F1", 10, "      " + t) for t in textwrap.wrap(s["why"], 92)]
        out.append(("F1", 4, ""))
    if change:
        out += [("F1", 6, "")] + [("F1", 10, t) for t in textwrap.wrap(change, 96)]
    out += [("F1", 10, ""), ("F1", 9, "Made by ForgeOS on this PC. Nothing was sent anywhere.")]
    return out


def fit(lines):
    """Everything on one page: drop the spacer lines, then make the small text smaller if needed."""
    room = PAGE_H - 110
    used = lambda ls: sum(int(sz * 1.35) for _, sz, _ in ls)  # noqa: E731
    if used(lines) > room:
        lines = [x for x in lines if x[2] or x[1] >= 10]
    if used(lines) > room:
        lines = [(f, 8 if sz <= 11 else sz, t) for f, sz, t in lines]
    return lines


def stream(lines):
    y, parts = PAGE_H - 60, ["BT"]
    for font, size, text in lines:
        if y < 50:
            break
        parts.append("/%s %d Tf 1 0 0 1 %d %d Tm (%s) Tj" % (font, size, LEFT, y, esc(text)))
        y -= int(size * 1.35)
    return ("\n".join(parts + ["ET"]) + "\n").encode("cp1252")


def write(c, change, path):
    body = stream(fit(page(c, change)))
    objs = [b"<< /Type /Catalog /Pages 2 0 R >>", b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 %d %d] /Contents 6 0 R "
            b"/Resources << /Font << /F1 4 0 R /F2 5 0 R >> >> >>" % (PAGE_W, PAGE_H),
            b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>",
            b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>",
            b"<< /Length %d >>\nstream\n" % len(body) + body + b"endstream"]
    out, where = b"%PDF-1.4\n", []
    for i, o in enumerate(objs, 1):
        where.append(len(out))
        out += b"%d 0 obj\n" % i + o + b"\nendobj\n"
    xref = len(out)
    out += b"xref\n0 %d\n0000000000 65535 f \n" % (len(objs) + 1)
    out += b"".join(b"%010d 00000 n \n" % w for w in where)
    out += b"trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (len(objs) + 1, xref)
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path + ".new", "wb") as f:
        f.write(out)
    os.replace(path + ".new", path)
    return path
