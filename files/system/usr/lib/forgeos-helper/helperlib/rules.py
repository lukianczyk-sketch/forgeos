"""Quick rules: pick the right tool instantly, with no AI. First rule that matches wins.

Returns (tool, argument) or None when no rule is sure (then the AI picks).
"""
import re

from .rulelist import LINK, PROGRAM_FILE, RULES

# Ransomware Tripwire (Job 16) goes right before Clean Sweep's "virus" words (rulelist.py is full).
RANSOM = ("ransomware", r"ransom|scrambl|tripwire|decrypt|encrypted (my|all|every)|"
                        r"(files|photos|pictures|documents|papers).{0,25}(locked|encrypted|scrambled|won.?t open)")
# Fake Tech Support Guard (Job 17) goes right before Scam Shield (a stranger in the PC is more than a scam check).
TECH = ("tech_support", r"anydesk|teamviewer|ultra ?viewer|screen ?connect|logmein|remote (control|access|desktop)|"
                        r"(get|got|getting|is|are|was|be) (in|into) my (computer|pc|laptop)|kick (them|him|her|someone|it) out|"
                        r"control(ling|s)? my (computer|pc|laptop|mouse|screen)|fake tech support|tech support scam|"
                        r"(mouse|cursor|pointer) (is )?moving (by|on) its own")
# Digital Will (Job 18) goes first ("if I die, how does my family get into my computer" is not a stranger).
WILL = ("digital_will", r"digital will|emergency envelope|legacy contact|inactive account manager|after my death|"
                        r"(if|when|after|in case|once) (i die|i pass( away)?|i.?m gone|i.?m dead|something happens to me)|"
                        r"when i.?m no longer (here|around)")
AT = [tool for tool, _rx in RULES].index("cleansweep_scan")
RULES2 = RULES[:AT] + [RANSOM] + RULES[AT:]
AT2 = [tool for tool, _rx in RULES2].index("scam_check")
COMPILED = [(tool, re.compile(rx, re.I)) for tool, rx in [WILL] + RULES2[:AT2] + [TECH] + RULES2[AT2:]]
REMEMBER = re.compile(r"^(please )?remember( that)?:? (.{3,200})$", re.I)
EVEN_BIGGER = re.compile(r"even bigger|bigger still|much bigger|biggest|still too small|very big", re.I)


def program_name(q):
    """The program a 'will it run' question is about: a file name, or the words after run/play/install."""
    m = PROGRAM_FILE.search(q)
    if m:
        return m.group(0)
    m = re.search(r"\b(?:run|play|install|use|will)\s+(.{2,60}?)(?:\s+(?:run|work|on (?:this|my|forgeos|linux)\b.*)|[?.!]|$)", q, re.I)
    name = m.group(1) if m else q
    name = re.sub(r"^(the|my|a|an)\s+", "", name.strip(), flags=re.I)
    return name.strip(" ?.!") or q


def match(question):
    """(tool, argument) from the quick rules, or None."""
    q = " ".join(question.split())
    m = REMEMBER.match(q)
    if m and not q.lower().startswith("remember when"):
        return ("remember", m.group(3).strip())
    if LINK.search(q) and not PROGRAM_FILE.search(q):
        return ("scam_check", q)
    for tool, rx in COMPILED:
        if rx.search(q):
            if tool == "text_bigger":
                return (tool, "bigger" if EVEN_BIGGER.search(q) else "big")
            if tool == "will_it_run":
                return (tool, program_name(q))
            if tool in ("scam_check", "find", "pc_question", "help_answer"):
                return (tool, q)
            return (tool, "")
    return None
