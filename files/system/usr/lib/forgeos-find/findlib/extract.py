"""ForgeOS Find Anything (Job 11): read the words inside one file.

Plain text, PDFs (scanned PDFs and photos are read with OCR), Word/Excel/
PowerPoint and LibreOffice files. Every tool runs on this PC only.
"""
import html
import os
import re
import shutil
import subprocess
import tempfile
import zipfile

MAX_TEXT = 200 * 1024          # words kept per file
MAX_READ = 50 * 1024 * 1024    # bigger files are found by name only
MAX_PHOTO = 30 * 1024 * 1024
MIN_PHOTO = 8 * 1024           # tiny pictures (icons) are found by name only
KINDS = {
    "text": ".txt .md .csv .log .json .xml .html .htm .rtf .ini .conf .eml",
    "pdf": ".pdf",
    "photo": ".jpg .jpeg .png .webp .tif .tiff .bmp .gif .heic",
    "document": ".docx .odt",
    "spreadsheet": ".xlsx .ods",
    "slides": ".pptx .odp",
}
ENDINGS = {e: k for k, v in KINDS.items() for e in v.split()}
# Which parts of an Office (zip) file hold the words.
OFFICE = {
    ".docx": r"word/document\.xml",
    ".xlsx": r"xl/sharedStrings\.xml",
    ".pptx": r"ppt/slides/slide[0-9]+\.xml",
    ".odt": r"content\.xml",
    ".ods": r"content\.xml",
    ".odp": r"content\.xml",
}
# Tags that end a paragraph, cell or line become a space; all other tags are removed.
BREAK = re.compile(r"</(?:w:p|a:p|text:p|text:h|si)>|<(?:w:tab|w:br|text:tab|text:s|text:line-break)\b[^>]*>")
TAG = re.compile(r"<[^>]*>")
LETTER = re.compile(r"[A-Za-z]")


def kind_of(path):
    """text, pdf, photo, document, spreadsheet, slides, or other (found by name only)."""
    return ENDINGS.get(os.path.splitext(path)[1].lower(), "other")


def run(cmd, timeout=60):
    """Run a tool, give up after <timeout> seconds, return what it printed."""
    try:
        done = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                              stdin=subprocess.DEVNULL, timeout=timeout, check=False)
    except (OSError, subprocess.SubprocessError):
        return ""
    return done.stdout.decode("utf-8", "replace")


def strip_tags(text):
    return html.unescape(TAG.sub("", BREAK.sub(" ", text)))


def plain(path):
    with open(path, "rb") as f:
        text = f.read(MAX_TEXT).decode("utf-8", "replace")
    if path.lower().endswith((".html", ".htm")):
        text = strip_tags(text)
    return text


def ocr(path):
    """Words printed in a photo or scan (English)."""
    if not shutil.which("tesseract"):
        return "", "photo text needs tesseract"
    return run(["tesseract", path, "-", "-l", "eng"]), ""


def pdf(path):
    """Words in a PDF. A scanned PDF (almost no letters) gets its first 3 pages read with OCR."""
    if not shutil.which("pdftotext"):
        return "", "PDF text needs poppler-utils"
    text = run(["pdftotext", "-l", "50", path, "-"])
    if len(LETTER.findall(text)) >= 20:
        return text, ""
    if not (shutil.which("pdftoppm") and shutil.which("tesseract")):
        return text, "scanned PDF text needs tesseract"
    with tempfile.TemporaryDirectory(prefix="forgeos-find-") as tmp:
        run(["pdftoppm", "-r", "200", "-png", "-l", "3", path, os.path.join(tmp, "page")], 120)
        for name in sorted(os.listdir(tmp)):
            text += " " + run(["tesseract", os.path.join(tmp, name), "-", "-l", "eng"])
    return text, ""


def office(path, ending):
    """Words in Word/Excel/PowerPoint and LibreOffice files (they are zip files of XML)."""
    want = re.compile(OFFICE[ending])
    parts = []
    try:
        with zipfile.ZipFile(path) as z:
            for name in sorted(z.namelist()):
                if want.fullmatch(name):
                    with z.open(name) as f:
                        parts.append(strip_tags(f.read(4 * MAX_TEXT).decode("utf-8", "replace")))
    except (OSError, zipfile.BadZipFile, RuntimeError, ValueError):
        return ""
    return " ".join(parts)


def extract(path, size):
    """Return (kind, words, note). note says which free tool is missing, or ""."""
    kind = kind_of(path)
    ending = os.path.splitext(path)[1].lower()
    text, note = "", ""
    try:
        if kind == "other" or size > MAX_READ:
            pass
        elif kind == "text":
            text = plain(path)
        elif kind == "pdf":
            text, note = pdf(path)
        elif kind == "photo":
            if ending != ".heic" and MIN_PHOTO <= size <= MAX_PHOTO:
                text, note = ocr(path)
        else:
            text = office(path, ending)
    except OSError:
        text = ""
    return kind, " ".join(text.split())[:MAX_TEXT], note
