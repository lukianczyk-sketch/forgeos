"""The right ForgeOS for the graphics card, and an NVIDIA driver blocked by Secure Boot.

forgeos = AMD / Intel graphics; forgeos-nvidia = NVIDIA open driver (GTX 16xx / RTX 20xx and newer).
Switching = 'rpm-ostree rebase' to the other signed image (asks for the PC password, one restart).
"""
import os

from . import SYS, run, start

NVIDIA = "10de"
SB_VAR = "SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c"
NVIDIA_IMAGE, PLAIN_IMAGE = "/forgeos-nvidia:", "/forgeos:"


def cards(items):
    return [it for it in items if it["kind"] == "graphics"]


def nvidia_cards(items):
    return [it for it in cards(items) if it["vendor"] == NVIDIA]


def new_enough(card):
    """The open NVIDIA driver needs Turing or newer (GTX 16xx, RTX 20xx+): device id 1e00 and up."""
    try:
        return int(card["device"], 16) >= 0x1E00
    except ValueError:
        return True


def which(ref):
    """'nvidia', 'plain' or '' (not a ForgeOS image) from the image reference."""
    if NVIDIA_IMAGE in ref:
        return "nvidia"
    if PLAIN_IMAGE in ref:
        return "plain"
    return ""


def advice(items, ref):
    """'ok', 'to-nvidia', 'to-plain', 'old-nvidia' (only an older NVIDIA card: the AMD/Intel version is
    right) or 'unknown' (not a ForgeOS image)."""
    now = which(ref)
    if not now:
        return "unknown"
    nv = nvidia_cards(items)
    good = [c for c in nv if new_enough(c)]
    if now == "plain" and good:
        return "to-nvidia"
    if now == "nvidia" and not good:
        return "to-plain"
    return "old-nvidia" if nv and not good else "ok"


def other_image(ref):
    if NVIDIA_IMAGE in ref:
        return ref.replace(NVIDIA_IMAGE, PLAIN_IMAGE, 1)
    if PLAIN_IMAGE in ref:
        return ref.replace(PLAIN_IMAGE, NVIDIA_IMAGE, 1)
    return ""


def switch(ref):
    """Rebase to the other ForgeOS image (the PC password is asked). True if it worked."""
    target = other_image(ref)
    if not target:
        return False
    return run(["rpm-ostree", "rebase", target], 3600)[0] == 0


def secure_boot():
    """True if Secure Boot is on (the last byte of the EFI SecureBoot variable is 1)."""
    try:
        with open(os.path.join(SYS, "firmware", "efi", "efivars", SB_VAR), "rb") as f:
            data = f.read()
        return bool(data) and data[-1] == 1
    except OSError:
        return False


def nvidia_loaded():
    return os.path.isdir(os.path.join(SYS, "module", "nvidia"))


def nvidia_problem(items, ref):
    """'' (fine), 'secure-boot' (driver blocked: the ForgeOS key is not enrolled) or 'not-loaded'."""
    if which(ref) != "nvidia" or not [c for c in nvidia_cards(items) if new_enough(c)] or nvidia_loaded():
        return ""
    return "secure-boot" if secure_boot() else "not-loaded"


def enroll_key():
    """Open a terminal that enrolls the ForgeOS Secure Boot key (password: universalblue)."""
    return start(["konsole", "-e", "ujust", "enroll-secure-boot-key"])
