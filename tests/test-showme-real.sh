#!/usr/bin/env bash
# Test for Show Me How (Job 22), case K: the REAL Tesseract reads a real picture of a screen (drawn with
# poppler from a small PDF, text at normal screen size) and finds where the words are. CI installs
# tesseract-ocr + poppler-utils (free, from the Ubuntu repos).
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-showme-real.sh <repo-root>
set -u
ROOT="$(cd "${1:-.}" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
for t in tesseract pdftoppm; do
  command -v "$t" >/dev/null 2>&1 || { echo "FAIL K ($t is not installed)"; exit 1; }
done
REAL_TESSERACT="$(command -v tesseract)"
# shellcheck source=tests/showme-fakes.sh
. "$ROOT/tests/showme-fakes.sh"
rm -f "$WORK/bin/tesseract"
ln -s "$REAL_TESSERACT" "$WORK/bin/tesseract"

# A 1280 x 720 "screen": a settings page with buttons in 13-point letters (PDF points = pixels at 72 dpi)
python3 - "$WORK/screen.pdf" <<'PYEOF'
import sys
NL = bytes([10])
items = [(60, 680, 15, "Printers"), (400, 400, 13, "Add Printer"), (900, 60, 13, "Cancel"),
         (60, 600, 13, "Configure Printer"), (1100, 680, 13, "Help")]
text = b" ".join(b"BT /F1 %d Tf %d %d Td (%s) Tj ET" % (s, x, y, t.encode()) for x, y, s, t in items)
objs = [b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 1280 720] /Contents 4 0 R"
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
pdftoppm -r 72 -png -singlefile "$WORK/screen.pdf" "$WORK/screen"

# K1: the real words and where they are: "Add Printer" (not "Configure Printer"), centre near x 0.35, y 0.44
OUT="$(python3 -B -c "
import sys; sys.path.insert(0, '$FORGEOS_SHOWME_LIB')
from showlib import screen
s = screen.read('$WORK/screen.png')
x, y, w, h = screen.find(s, 'Add Printer')
c = screen.find(s, 'Cancel')
print(s[0], s[1], round(x + w / 2, 2), round(y + h / 2, 2), round(c[0], 2), round(c[1], 2), screen.find(s, 'Remove Printer'))
")"
echo "  read: $OUT"
check K1 'python3 -c "
import sys
a = sys.argv[1].split()
assert a[:2] == [\"1280\", \"720\"], a
assert abs(float(a[2]) - 0.35) <= 0.02 and abs(float(a[3]) - 0.44) <= 0.02, a
assert abs(float(a[4]) - 0.70) <= 0.02 and abs(float(a[5]) - 0.90) <= 0.03 and a[6] == \"None\", a
" "$OUT"'
# K2: a whole walk on the real picture (pretend screenshot = this picture): it points at Add Printer
cp "$WORK/screen.png" "$WORK/real.png"
fake spectacle 'while [ $# -gt 0 ]; do [ "$1" = -o ] && cp "$WORK/real.png" "$2"; shift; done; exit 0'
mkdir -p "$WORK/share/guides"
printf '# Test\nwords: test\nopen: none\nstep: word Add Printer | Click Add Printer.\n' > "$WORK/share/guides/test.txt"
OUT="$(FORGEOS_SHOWME_SHARE="$WORK/share" FORGEOS_SHOWME_LOOKS=1 SM guide test --no-draw)"
check K2 'grep -q "^VIEW${T}point${T}1/1${T}0.31[0-9]* 0.4[0-9]* " <<< "$OUT" && [ ! -e "$WORK/run/forgeos-showme-$(id -u)/screen.png" ]'

echo
if [ "$failures" -eq 0 ]; then echo "Show Me How real-OCR test (K) passed."; else echo "Show Me How real-OCR test failed."; exit 1; fi
