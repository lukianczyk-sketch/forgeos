"""Your helper for "Call for help": their name, mobile number and RustDesk ID (all on this PC only).

~/.config/forgeos/family.conf, readable by you only. Lines: key=value.
"""
import re

from . import CONF, clean, write_private

FIELDS = ("name", "phone", "rustdesk_id", "me")


def load():
    found = {}
    try:
        with open(CONF) as f:
            for line in f:
                key, sep, value = line.rstrip("\n").partition("=")
                if sep and key in FIELDS:
                    found[key] = clean(value)
    except OSError:
        pass
    return found if found.get("name") else {}


def check_phone(text):
    """A mobile number: digits with optional + - ( ) . and spaces, 7 to 15 digits. '' = none."""
    text = clean(text, 30)
    if not text:
        return ""
    digits = re.sub(r"\D", "", text)
    if not re.fullmatch(r"\+?[\d\s().-]+", text) or not 7 <= len(digits) <= 15:
        raise ValueError("That mobile number doesn't look right. Use only numbers, like 661-555-0123.")
    return ("+" if text.startswith("+") else "") + digits


def check_id(text):
    """A RustDesk ID: 6 to 12 digits (spaces are fine). '' = none."""
    text = re.sub(r"\s", "", clean(text, 30))
    if not text:
        return ""
    if not re.fullmatch(r"\d{6,12}", text):
        raise ValueError("A RustDesk ID is a number of 6 to 12 digits, like 123 456 789. "
                         "Your helper sees it at the top of RustDesk on their PC or phone.")
    return text


def save(name, phone="", rustdesk_id="", me=""):
    name = clean(name, 40)
    if not name:
        raise ValueError("Please type your helper's name.")
    data = {"name": name, "phone": check_phone(phone), "rustdesk_id": check_id(rustdesk_id),
            "me": clean(me, 40)}
    write_private(CONF, "".join("%s=%s\n" % (k, data[k]) for k in FIELDS))
    return data


def forget():
    write_private(CONF, "")


def nice_id(digits):
    return " ".join(digits[i:i + 3] for i in range(0, len(digits), 3))
