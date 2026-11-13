"""Quick rules: pick the right tool instantly, with no AI. First rule that matches wins.

Returns (tool, argument) or None when no rule is sure (then the AI picks).
"""
import re

from .netask import NET
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
# Find My PC (Job 19) goes first too ("my laptop was stolen" is not a scam check or a search for files).
LOC = ("find_my_pc", r"find my (pc|computer|laptop|notebook)|anti.?theft|someone stole my (pc|computer|laptop)|"
                     r"(lost|stolen|misplaced) my (pc|computer|laptop)|where is my (laptop|notebook)|"
                     r"(pc|computer|laptop) (was|got|is|has been|been) (lost|stolen|missing|taken)(?!\s+(a|an|the|some|my|its)\b)|"
                     r"track (my|a) (lost |stolen )?(pc|computer|laptop)|(lost|stolen) (pc|computer|laptop)")
# Why Is It Slow? (Job 20) goes right before the other PC problems ("my internet is slow" is checked there too).
SLOW = ("why_slow", r"\bslow(ly|er|ness|s|ed|ing)?\b|sluggish|\blag(gy|ging|s)?\b|takes (forever|ages)|"
                    r"speed (it |this |my \w+ )?up|(make|making|get) (it|my \w+|this \w+) (faster|quicker)")
# PC Report Card (Job 21) goes right before Why Is It Slow? (emergencies like ransomware or a scam win first).
CARD = ("report_card", r"report ?card|how (healthy|good|well) is (my|this|the) (pc|computer|laptop)|"
                       r"(pc|computer|laptop).{0,3} (overall )?(health|grade|score)\b|grade (does )?(my|this) (pc|computer|laptop)|"
                       r"(health|check).?up (on|for) (my|this) (pc|computer|laptop)|"
                       r"is (my|this) (pc|computer|laptop) (healthy|in good shape)\b(?! enough)")
# Show Me How (Job 22) goes right after Why Is It Slow? (emergencies, Undo, Find, bigger text, calling the
# helper, the report card and slowness win first; it comes before the other PC problems like Wi-Fi).
SHOW = ("show_me", r"\bshow me (how|where (to|do i) click)\b|walk me through|guide me (through|to)|"
                   r"where do i click|point (to|at|out) (it|where|the)")
# Plain-English Errors (Job 23): an error's words or code go right after Show Me How ("show me how to fix
# this error" is a walk); loose words ("it shows an error") only right after the other PC problems (Wi-Fi...).
ERR = ("explain_error", r"what does (this|that|the|my|it) .{0,20}(error|message|code|warning) mean|"
                        r"explain (this|that|the) (error|message)|\b(error|stop) (code|number)\b|\b0x[0-9a-f]{8}\b|"
                        r"\berr_[a-z_]{4,}|\.dll\b.{0,30}(missing|not found)")
ERR2 = ("explain_error", r"\b(error|warning) message\b|(got|getting|keep getting|says|said|shows|showing|popped up with)"
                         r" (an |this |a )?(weird |strange )?error\b")
AT = [tool for tool, _rx in RULES].index("cleansweep_scan")
AT3 = [tool for tool, _rx in RULES].index("pc_question")
RULES2 = RULES[:AT] + [RANSOM] + RULES[AT:AT3] + [CARD, SLOW, SHOW, ERR, NET] + RULES[AT3:AT3 + 1] + [ERR2] + RULES[AT3 + 1:]
AT2 = [tool for tool, _rx in RULES2].index("scam_check")
COMPILED = [(tool, re.compile(rx, re.I)) for tool, rx in [LOC, WILL] + RULES2[:AT2] + [TECH] + RULES2[AT2:]]
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
            if tool in ("scam_check", "find", "pc_question", "help_answer", "show_me", "explain_error", "net_access"):
                return (tool, q)
            return (tool, "")
    return None
