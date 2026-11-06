"""Does a file look scrambled (encrypted by ransomware)? Only the first 64 KB are looked at.

Scrambled data looks like pure noise (randomness close to 8 bits per byte). Photos, music, videos, zip
and Office files are noisy too, but they start with their own fixed "signature" bytes; a scrambled copy
has lost them. Small files (under 1 KB) are not judged: the bait files catch attacks on those.
"""
import math
import os
import re
from collections import Counter

HEAD = 65536
SMALLEST = 1024
NOISY = 7.5
PARTIAL = (".crdownload", ".part", ".download", ".partial")  # a download that is still coming in
ZIP = b"PK\x03\x04"
OLE = b"\xd0\xcf\x11\xe0"
SIGNS = [("jpg jpeg jfif", 0, b"\xff\xd8\xff"), ("png", 0, b"\x89PNG"), ("gif", 0, b"GIF8"), ("bmp", 0, b"BM"),
         ("zip docx xlsx pptx odt ods odp epub jar apk xpi cbz", 0, ZIP), ("doc xls ppt msi", 0, OLE),
         ("pdf", 0, b"%PDF"), ("gz tgz", 0, b"\x1f\x8b"), ("7z", 0, b"7z\xbc\xaf"), ("rar cbr", 0, b"Rar!"),
         ("xz", 0, b"\xfd7zXZ"), ("zst", 0, b"\x28\xb5\x2f\xfd"), ("bz2", 0, b"BZh"),
         ("mp4 m4a m4v mov heic heif 3gp avif", 4, b"ftyp"), ("webp avi wav", 0, b"RIFF"),
         ("ogg opus oga", 0, b"OggS"), ("flac", 0, b"fLaC"), ("mkv webm", 0, b"\x1a\x45\xdf\xa3"),
         ("mp3", 0, b"ID3"), ("mp3", 0, b"\xff\xfb"), ("mp3", 0, b"\xff\xf3"), ("mp3", 0, b"\xff\xf2"),
         ("exe dll", 0, b"MZ"), ("appimage so", 0, b"\x7fELF"), ("rpm", 0, b"\xed\xab\xee\xdb"),
         ("deb", 0, b"!<arch>"), ("iso", 32769, b"CD001"), ("kdbx", 0, b"\x03\xd9\xa2\x9a"),
         ("tif tiff", 0, b"II*\x00"), ("tif tiff", 0, b"MM\x00*"), ("psd", 0, b"8BPS")]
MAGIC = {}
for _ends, _at, _sig in SIGNS:
    for _end in _ends.split():
        MAGIC.setdefault("." + _end, []).append((_at, _sig))
NOTE_ENDS = (".txt", ".html", ".htm", ".hta", ".url", ".rtf")
NOTE_RX = re.compile(r"(how|help)[ _.-]*(to)?[ _.-]*(decrypt|recover|restore|unlock|get[ _.-]*back)|"
                     r"decrypt|ransom|restore[ _.-]*(my|your)?[ _.-]*files|your[ _.-]*files|"
                     r"files[ _.-]*(are|were)[ _.-]*(encrypted|locked)|read[ _.-]*me[ _.-]*now|^!+[ _.-]*read", re.I)


def ending(name):
    """The real file ending in lower case: 'Tax.PDF' -> '.pdf'; 'x.zip.crdownload' -> '.zip'."""
    low = name.lower()
    for part in PARTIAL:
        if low.endswith(part):
            low = low[:-len(part)]
    return os.path.splitext(low)[1]


def randomness(data):
    """Bits of randomness per byte (0 = all the same, 8 = pure noise)."""
    if not data:
        return 0.0
    n = float(len(data))
    return -sum(c / n * math.log2(c / n) for c in Counter(data).values())


def is_note(name):
    return ending(name) in NOTE_ENDS and bool(NOTE_RX.search(name))


def judge(name, data):
    """'note' (a ransom note), 'scrambled', or '' (looks normal)."""
    if is_note(name):
        return "note"
    if data is None or len(data) < SMALLEST or randomness(data) < NOISY:
        return ""
    for at, sign in MAGIC.get(ending(name), []):
        if data[at:at + len(sign)] == sign:
            return ""
    return "scrambled"


def read_head(path):
    """The first 64 KB of a file (never follows a symlink); None if it can't be read."""
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    except OSError:
        return None
    try:
        return os.read(fd, HEAD)
    except OSError:
        return None
    finally:
        os.close(fd)
