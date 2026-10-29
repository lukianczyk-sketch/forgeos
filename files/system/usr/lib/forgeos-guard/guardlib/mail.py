"""Email Guard: check one email with Scam Shield and virus-check its attachments (in memory, never saved).

Thunderbird's own files are only read, never changed.
"""
import email
import email.policy
import email.utils
import html
import io
import os
import re
import tempfile
import zipfile

from . import SCAMSHIELD, clean, log_event, private_dir, risky_name, run, STATE_DIR
from . import alerts, scan

SKIP = re.compile(r"^(trash|junk|spam|bulk|sent|sent items|sent mail|drafts|templates|outbox|unsent messages|deleted|deleted items)$", re.I)


def skip_folder(path):
    """Junk, Trash, Sent, Drafts... are not checked (you wrote them, or they are already thrown away)."""
    return any(SKIP.match(part.rsplit(".sbd", 1)[0]) for part in path.split(os.sep) if part)


def text_of(msg):
    """Sender, subject and the words of the email; link addresses from HTML are kept."""
    parts = []
    for part in msg.walk():
        if part.get_content_maintype() != "text" or part.get_filename():
            continue
        try:
            body = part.get_content()
        except (LookupError, ValueError, AssertionError):
            body = (part.get_payload(decode=True) or b"").decode("utf-8", "replace")
        if part.get_content_subtype() == "html":
            links = re.findall(r"""href\s*=\s*["']?([^"' >]+)""", body, re.I)
            body = re.sub(r"(?is)<(script|style)\b.*?</\1>", " ", body)
            body = html.unescape(re.sub(r"<[^>]+>", " ", body)) + "\n" + "\n".join(links)
        parts.append(body)
    head = "From: %s\nReply-To: %s\nSubject: %s\n\n" % (msg.get("From", ""), msg.get("Reply-To", ""), msg.get("Subject", ""))
    return head + "\n".join(parts)[:20000]


def zip_names(data):
    try:
        with zipfile.ZipFile(io.BytesIO(data)) as z:
            return z.namelist()[:500]
    except (zipfile.BadZipFile, OSError, ValueError, RuntimeError):
        return []


def attachments(msg):
    """[(name, why risky or '', virus name / '' / None)] for every attachment."""
    found = []
    for part in msg.walk():
        name = part.get_filename()
        if not name or part.is_multipart():
            continue
        data = part.get_payload(decode=True) or b""
        why = risky_name(name)
        if not why and name.lower().endswith(".zip"):
            inside = [n for n in zip_names(data) if risky_name(os.path.basename(n))]
            if inside:
                why = "a zip file with a program inside (%s)" % os.path.basename(inside[0])
        if not why and re.search(r"\.s?html?$", name, re.I):
            why = "a web page - fake login pages come this way"
        found.append((clean(name, 80), why, scan.scan_bytes(data)))
    return found


def scamshield(text, ai):
    """(level, words) from Scam Shield: 2 scam, 1 be careful, 0 fine, -1 could not check."""
    tmp = tempfile.NamedTemporaryFile("w", dir=private_dir(STATE_DIR), prefix=".mail-", delete=False)
    try:
        with tmp:
            tmp.write(text)
        code, out = run([SCAMSHIELD, "check"] + ([] if ai else ["--no-ai"]) + [tmp.name], 300)
    finally:
        os.remove(tmp.name)
    return (code if code in (0, 1, 2) else -1), out


def check(msg, folder=""):
    """Check one email; warn and log if needed. Returns 2 virus/scam, 1 be careful, 0 fine."""
    sender = clean(email.utils.parseaddr(msg.get("From", ""))[1] or msg.get("From", "someone"), 80)
    subject = clean(msg.get("Subject", "(no subject)"), 80)
    worst, why = 0, []
    for name, risky, virus in attachments(msg):
        if virus:
            worst = 2
            why.append("The attachment %s has a virus: %s. Don't open it." % (name, virus))
        elif risky:
            worst = max(worst, 1)
            why.append("The attachment %s is %s." % (name, risky))
    text = text_of(msg)
    level, out = scamshield(text, ai=False)
    if level == 1:
        level, out = scamshield(text, ai=True)
    if level > 0:
        why.append(out.strip())
    worst = max(worst, level)
    if worst:
        eid = log_event("scam" if worst >= 2 else "careful", "email", sender, subject, folder,
                        "From: %s\nSubject: %s\n\n%s\n" % (sender, subject, "\n\n".join(why)))
        alerts.email(worst, sender, subject, eid)
    return worst


def parse(data):
    return email.message_from_bytes(data, policy=email.policy.default)
