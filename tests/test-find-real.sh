#!/usr/bin/env bash
# Test for Find Anything (Job 11), case U: the REAL free tools (tesseract OCR + poppler pdftotext)
# read a real PDF and a real picture of printed text. CI installs tesseract-ocr + poppler-utils.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-find-real.sh <repo-root>
set -u
ROOT="$(cd "${1:-.}" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
FIND="$ROOT/files/system/usr/bin/forgeos-find"
export FORGEOS_FIND_LIB="$ROOT/files/system/usr/lib/forgeos-find" PYTHONDONTWRITEBYTECODE=1
for t in tesseract pdftotext pdftoppm; do
  command -v "$t" >/dev/null 2>&1 || { echo "FAIL U ($t is not installed)"; exit 1; }
done

# U: the real tools read a real one-page PDF and a real picture of the same page.
mkdir -p "$WORK/home" "$WORK/data"
export HOME="$WORK/home" XDG_DATA_HOME="$WORK/data" XDG_CONFIG_HOME="$WORK/cfg"
python3 - "$HOME/invoice.pdf" <<'PYEOF'
import sys
NL = bytes([10])
text = b"BT /F1 36 Tf 60 650 Td (INVOICE 4471 PAID IN FULL) Tj ET"
objs = [b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R"
        b" /Resources << /Font << /F1 5 0 R >> >> >>",
        b"<< /Length %d >>" % len(text) + NL + b"stream" + NL + text + NL + b"endstream",
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"]
out, offsets = b"%PDF-1.4" + NL, []
for n, obj in enumerate(objs, 1):
    offsets.append(len(out))
    out += b"%d 0 obj" % n + NL + obj + NL + b"endobj" + NL
xref = len(out)
rows = [b"xref", b"0 %d" % (len(objs) + 1), b"0000000000 65535 f "]
rows += [b"%010d 00000 n " % o for o in offsets]
rows += [b"trailer", b"<< /Size %d /Root 1 0 R >>" % (len(objs) + 1), b"startxref", b"%d" % xref, b"%%EOF"]
with open(sys.argv[1], "wb") as f:
    f.write(out + NL.join(rows) + NL)
PYEOF
# The picture: pdftoppm draws the page as photo-1.png (about 14 KB, so it is read with OCR).
pdftoppm -r 100 -png -l 1 "$HOME/invoice.pdf" "$HOME/photo"
OUT="$(python3 "$FIND" index)"
OUT2="$(python3 "$FIND" search 4471)"
check U1 'grep -q "2 files read" <<< "$OUT" && [ "$(grep -c "^RESULT" <<< "$OUT2")" -eq 2 ]'
check U2 'grep -q "^RESULT.$HOME/invoice.pdf.pdf.*[[]4471[]]" <<< "$OUT2" && grep -q "^RESULT.$HOME/photo-1.png.photo.*[[]4471[]]" <<< "$OUT2"'

echo
if [ "$failures" -eq 0 ]; then echo "Find Anything real-tools test (U) passed."; else echo "Find Anything real-tools test failed."; exit 1; fi
