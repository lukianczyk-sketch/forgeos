"""Fake error messages: the scam check comes BEFORE the library (a fake "virus" alert must never get a
calm card). Real errors never show a phone number and never ask for money, so those are the main signs.
"""
import re

PHONE = re.compile(r"(\+?1[\s.-]?)?\(?\b[2-9]\d{2}\)?[\s.-]\d{3}[\s.-]\d{4}\b|\b1[\s.-]?8(00|33|44|55|66|77|88)\b")
SCARY = re.compile(r"virus|infected|infection|hacked|hacker|trojan|spyware|malware|pornographic|security (alert|breach|warning)|"
                   r"(pc|computer|device|windows|system|account) (is |has been )?(locked|blocked|suspended|disabled|compromised)|"
                   r"license (has )?expired|subscription (has )?expired|unauthori[sz]ed (access|activity|purchase)|"
                   r"call (microsoft|apple|windows|support|technician|the number|now|immediately)|"
                   r"(microsoft|windows|apple|amazon|paypal|norton|mcafee|geek squad) (support|security|defender|helpdesk|help desk)", re.I)
MONEY = re.compile(r"gift ?cards?|bitcoin|crypto|wire (the |a )?(money|transfer)|zelle|western union|"
                   r"pay (now|a fee|the fee|to unlock|to restore)|renewal fee|refund (department|team)", re.I)
PUSH = re.compile(r"do not (close|turn off|shut ?down|restart|ignore)|immediately|within \d+ (minutes|hours)|"
                  r"final (warning|notice)|act now|will be (deleted|erased|lost|disabled)", re.I)
CLICK = re.compile(r"(click|tap|press) (here|ok|allow|the button|below)|download (the|this) (fix|cleaner|tool)|"
                   r"scan (now|your (pc|computer))|(fix|clean|remove) (it|them|viruses) now", re.I)
ERRORWORDS = re.compile(r"\b(error|warning|alert|failed|failure|problem|crash(ed)?|code)\b", re.I)


def signs(text):
    """The scam signs in TEXT, as short plain words (an empty list = no signs)."""
    out = []
    if PHONE.search(text):
        out.append("it shows a phone number to call")
    if MONEY.search(text):
        out.append("it asks for money, gift cards or crypto")
    if SCARY.search(text):
        out.append("it tries to scare you with words like virus, locked or expired")
    if PUSH.search(text):
        out.append("it rushes you")
    if CLICK.search(text):
        out.append("it wants you to click or download something")
    return out


def is_fake(text):
    """A fake error: money + (scary words, a phone number or a rush); a phone number + (scary words, money or
    error words: real errors never give a number to call); scary words + a rush or a click."""
    has = lambda rx: bool(rx.search(text))  # noqa: E731
    if has(MONEY) and (has(SCARY) or has(PHONE) or has(PUSH)):
        return True
    if has(PHONE) and (has(SCARY) or has(ERRORWORDS)):
        return True
    return has(SCARY) and (has(PUSH) or has(CLICK))


def card(text):
    """The red card for a fake error."""
    s = signs(text)
    return {"id": "scam-fake-error", "level": "red", "title": "This is a scam, not a real error",
            "say": "This message is fake. It was made by scammers: %s." % "; ".join(s),
            "do": "Do not call any number and do not pay anything. Close it with the button below, or hold Alt"
                  " and press F4. Your PC is fine. If you already called or let someone in, open Fake Tech"
                  " Support Guard.", "fix": "techguard:escape"}
