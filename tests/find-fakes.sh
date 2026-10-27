# shellcheck shell=bash
# Fake tools for the Find Anything tests (Job 11). Sourced by tests/test-find*.sh.
# Every fake writes its name and arguments to $WORK/calls.log.
# shellcheck disable=SC2016  # the fake scripts are written out single-quoted on purpose
mkdir -p "$WORK/bin" "$WORK/home" "$WORK/cfg/forgeos" "$WORK/data"
fake() { printf '#!/usr/bin/env bash\necho "%s $*" >> "$WORK/calls.log"\n%s\n' "$1" "$2" > "$WORK/bin/$1"; chmod +x "$WORK/bin/$1"; }

# Fake OCR: the words "printed" in a picture depend on its file name.
fake tesseract 'case "$1" in
  *receipt*) echo "WALMART RECEIPT TOTAL 42.17" ;;
  *license*) echo "CALIFORNIA DRIVER LICENSE DL 1234567" ;;
  *page-1.png) echo "RESIDENTIAL LEASE AGREEMENT" ;;
  *page-2.png) echo "MONTHLY RENT 1500" ;;
esac'
# Fake PDF reader: a scanned PDF (name has "scan") has no words, so OCR must read it.
fake pdftotext 'case "$3" in *scan*) echo " " ;; *) echo "Bank statement for account ending 9921, closing balance" ;; esac'
# Fake pdftoppm: makes two page pictures named PREFIX-1.png and PREFIX-2.png.
fake pdftoppm 'for a in "$@"; do last="$a"; done; : > "$last-1.png"; : > "$last-2.png"'
fake xdg-open 'exit 0'
fake dolphin 'exit 0'
fake dbus-send 'exit 0'
fake setsid 'shift; "$@"'

# Fake kdialog: the text box answers from $WORK/input, menus from $WORK/menu (one per line;
# none left = Cancel), Yes/No answers FAKE_YES (0 = yes). Menus and boxes are logged to $WORK/shown.
fake kdialog 'for a in "$@"; do case "$a" in
  --menu) printf "%s\n" "$@" >> "$WORK/shown"; l="$(head -n 1 "$WORK/menu" 2>/dev/null)"; sed -i 1d "$WORK/menu" 2>/dev/null; [ -n "$l" ] || exit 1; echo "$l"; exit 0 ;;
  --inputbox) l="$(head -n 1 "$WORK/input" 2>/dev/null)"; sed -i 1d "$WORK/input" 2>/dev/null; [ -n "$l" ] || exit 1; echo "$l"; exit 0 ;;
  --yesno) exit "${FAKE_YES:-0}" ;;
  --msgbox|--error|--sorry) printf "%s\n" "$@" >> "$WORK/shown"; exit 0 ;;
  --progressbar) echo "org.fake /bar"; exit 0 ;;
esac; done; exit 0'


# start_fake_ollama: start the fake Ollama (tests/find-fake-ollama.py) and point Find Anything at it.
start_fake_ollama() {
  python3 "$ROOT/tests/find-fake-ollama.py" "$WORK" &
  OLLAMA_PID=$!
  for _ in $(seq 50); do [ -s "$WORK/ai-port" ] && break; sleep 0.1; done
  FORGEOS_OLLAMA_URL="http://127.0.0.1:$(cat "$WORK/ai-port")"
  export FORGEOS_OLLAMA_URL
  trap 'kill "$OLLAMA_PID" 2>/dev/null; rm -rf "$WORK"' EXIT
}
# ai WORDS-JSON [KIND] [AFTER] [BEFORE]: what the fake AI answers next.
ai() { printf '{"words":%s,"kind":"%s","after":"%s","before":"%s"}' "$1" "${2:-any}" "${3:-}" "${4:-}" > "$WORK/ai-answer"; }

# make_office FILE INNER-PATH TEXT: a tiny Word/Excel/PowerPoint/LibreOffice file (a zip of XML).
make_office() {
  python3 - "$@" <<'PYEOF'
import sys, zipfile
path, inner, text = sys.argv[1:4]
# Each word is its own "run", like Word makes them; the space is inside the run.
words = "".join('<w:r><w:t xml:space="preserve">%s </w:t></w:r>' % w for w in text.split(" "))
xml = '<?xml version="1.0"?><doc><w:p>' + words + '</w:p><w:p>&amp; more</w:p></doc>'
with zipfile.ZipFile(path, "w") as z:
    z.writestr("[Content_Types].xml", "<Types/>")
    z.writestr(inner, xml)
PYEOF
}

# A home folder with one file of every kind. Photos must be 8 KB or more to be read with OCR.
H="$WORK/home"
mkdir -p "$H/Documents/Taxes/2023" "$H/Pictures" "$H/.private" "$H/Skipme" "$H/node_modules/x" "$H/Games" "$WORK/outside"
echo "Shopping list: milk, eggs and coffee" > "$H/Documents/list.txt"
echo "<html><body><p>Garage sale on <b>Saturday</b></p></body></html>" > "$H/Documents/sale.html"
make_office "$H/Documents/budget.docx" word/document.xml "Quarterly budget forecast"
make_office "$H/Documents/miles.xlsx" xl/sharedStrings.xml "Mileage log Tehachapi"
make_office "$H/Documents/garden.pptx" ppt/slides/slide1.xml "Garden plan tomatoes"
make_office "$H/Documents/chili.odt" content.xml "Recipe for green chili"
echo "x" > "$H/Documents/statement.pdf"
echo "x" > "$H/Documents/scan-lease.pdf"
echo "Federal tax return" > "$H/Documents/Taxes/2023/return.txt"
head -c 9000 /dev/zero > "$H/Pictures/receipt.jpg"
head -c 9000 /dev/zero > "$H/Pictures/license.png"
head -c 100 /dev/zero > "$H/Pictures/tiny-license-icon.png"
head -c 100 /dev/zero > "$H/Pictures/holiday.mp4"
echo "zebra password" > "$H/.private/secret.txt"
echo "zebra skipped" > "$H/Skipme/skip.txt"
echo "zebra module" > "$H/node_modules/x/mod.txt"
echo "zebra game" > "$H/Games/game.txt"
echo "zebra outside" > "$WORK/outside/out.txt"
ln -s "$WORK/outside" "$H/link-to-outside"
echo "$H/Skipme" > "$WORK/cfg/forgeos/find-skip.txt"

export WORK HOME="$H" PATH="$WORK/bin:$PATH" XDG_CONFIG_HOME="$WORK/cfg" XDG_DATA_HOME="$WORK/data"
export FORGEOS_FIND_LIB="$ROOT/files/system/usr/lib/forgeos-find" FORGEOS_OLLAMA_URL="http://127.0.0.1:9"
export PYTHONDONTWRITEBYTECODE=1
FIND="$ROOT/files/system/usr/bin/forgeos-find"
export DB="$WORK/data/forgeos/find/index.db"
# git keeps the scripts without the "run" bit, so the window calls the engine through a wrapper.
printf '#!/usr/bin/env bash\nexec python3 "%s" "$@"\n' "$FIND" > "$WORK/engine"
chmod +x "$WORK/engine"
export FORGEOS_FIND_ENGINE="$WORK/engine"

# F: run Find Anything. first <output>: the first file found.
F() { python3 "$FIND" "$@"; }
first() { awk -F '\t' '$1 == "RESULT" {print $2; exit}' <<< "$1"; }
# sent: what was sent to the AI, one fact per line.
sent() {
  python3 - "$WORK/ai-body.json" <<'PYEOF'
import json, sys
b = json.load(open(sys.argv[1]))
p = b["format"]["properties"]
print("model=%s stream=%s temperature=%s" % (b["model"], b["stream"], b["options"]["temperature"]))
print("kinds=%s maxwords=%s" % (" ".join(p["kind"]["enum"]), p["words"]["maxItems"]))
print("system=" + b["messages"][0]["content"])
print("question=" + b["messages"][1]["content"])
PYEOF
}
