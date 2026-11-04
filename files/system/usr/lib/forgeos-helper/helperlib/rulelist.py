"""The quick rules' word patterns, in order: the first one that matches picks the tool (see rules.py).

Safety first: requests no tool may do go to just_answer, which explains it can't.
"""
import re

LINK = re.compile(r"(https?://|www\.)\S+|\b[a-z0-9-]+\.(com|net|org|info|xyz|top|biz|us|co|io|ru|cn|shop|club|site|online)(/\S*)?\b", re.I)
PROGRAM_FILE = re.compile(r"\S+\.(exe|msi|apk|appimage|deb|rpm|flatpakref)\b", re.I)
FILE_WORDS = (r"(file|files|photo|photos|picture|pictures|pic|document|documents|letter|pdf|receipt|"
              r"paper|papers|tax|taxes|recipe|spreadsheet|statement|form|resume|scan|video|song|music)")
TOOL_NAMES = (r"(forge helper|scam shield|ask your pc|will it run|find anything|ghostfinder|ghost finder|always-on guard|"
              r"guard|family mode|call for help|undo button|privacy report|clean sweep|panic button|all clear|ai setup|kde connect)")
RULES = [
    ("just_answer", r"(neighbou?r|someone else|other people|wife|husband|without (them|her|him) knowing).{0,40}(password|camera|record|spy|read|track)|"
                    r"write (me )?(a )?(virus|malware|trojan)|root access|developer mode|rm -rf|format (the |my )?(drive|disk)|delete (every|all)\b|crack(ed)? "),
    ("help_answer", r"^(what|what.?s|who) (is|are|does) (the |a )?" + TOOL_NAMES + r"\b"),
    ("forget_all", r"^(please )?forget (everything|all)( you know| about me)?\b"),
    ("memory_show", r"what do you (remember|know) about me|what have i told you"),
    ("panic", r"^\W*panic\b|panic (now|button now)|cut (off )?(the |my )?(internet|camera|webcam)|kill (the |my )?(camera|webcam|mic)"),
    ("guard_status", r"\bguard\b|quarantin|locked away|blocked (a |my |the )?(download|file|site|website|email)|download (was|got) (blocked|stopped)|download.{0,20}blocked"),
    ("drivers", r"\bdrivers?\b(?!'s|s'| licen[cs]e)|\bbios\b|\buefi\b|firmware|device manager"),
    ("moving_day", r"moving day|\b(move|bring|copy|transfer|get|put|take)\b.{0,40}\b(from|off) (my |the )?(old|other|previous|last|windows) (pc|computer|laptop|drive|machine)\b|"
                   r"\bfrom windows (to|onto|into|over to) (forgeos|this|linux)|\b(old|previous) (pc|computer|laptop).{0,30}\b(to|onto) (this|my new|the new|forgeos)"),
    ("drive_health", r"drive health|\b(hard ?drive|drive|disk|ssd|nvme)s?\b.{0,30}\b(dying|dead|fail(ing)?|going bad|healthy?|ok(ay)?|worn|clicking|grinding)\b|"
                     r"bad sectors?|smart (status|data)|(clicking|grinding).{0,30}\b(drive|disk)"),
    ("switch_windows", r"\b(restart|reboot|boot|switch|go|start|get)( back)? (in)?to windows\b|dual.?boot|restart into forgeos|switch (between )?(windows|forgeos) and"),
    ("scam_check", r"\bscam|phish|is (this|it) (real|legit|safe|a trick|fake)|gift ?cards?|\birs\b|won (a|the) (prize|lottery)|lottery|"
                   r"suspicious (email|text|message|call|link)|(tech|microsoft|apple|amazon) (support )?called|"
                   r"(call|called|phone call) from (windows|microsoft|apple|amazon|tech)|(a man|a woman|someone|somebody|caller|a guy) on the phone|"
                   r"subscription.{0,30}renew|renewed.{0,40}call|reply with (your |my )?(ssn|social|password|bank|pin)|medicare card|"
                   r"(wants|asked for|asking for) my (password|bank|social|ssn|card|code)|pop.?up says .*(virus|infected|call)|"
                   r"fake (email|text|message|website|site)|(email|text) (says|from) .*(bank|paypal|amazon|police|irs)"),
    ("ghost_sweep", r"tracker|air ?tag|tile tag|hidden (camera|device|bug|mic)|bugged|being tracked|follow(ing|ed) me|spy (device|gadget)|"
                    r"strange device|unknown device|who is on my (wi-?fi|internet|network)"),
    ("privacy_report", r"camera (light|came on|turned on|is on)|who (used|is using|turned on) (my )?(camera|webcam|mic|microphone)|"
                       r"(apps?|programs?) (used|using|listening|spying)|listening to me|privacy report|spying on me|recording my screen"),
    ("cleansweep_scan", r"hack|virus|malware|trojan|ransom|infected|spyware|keylogger|been compromised"),
    ("undo_open", r"\bundo\b|deleted|get (it|my \w+|the \w+) back|older version|old version|overwrote|saved over|restore (my |a |the )?(file|folder|photo|document)|went back in time"),
    ("find", r"(where did (i|my)|where.?d i put|can.?t|cannot|could not|couldn.?t|help me|where.?s|where is|where are|find|looking for|lost|misplaced|search for) .*\b" + FILE_WORDS + r"\b"),
    ("will_it_run", r"\bwill .{1,60} (run|work)\b|can i (run|install|play|use) |does .{1,60} work on (this|my|forgeos|linux)|windows (program|game|app|software)|\.(exe|msi|apk)\b"),
    ("text_bigger", r"(bigger|larger|enlarge|increase|make).{0,30}(text|letters|font|words|writing|print|everything)|"
                    r"(text|letters|font|words|writing|print).{0,20}(too small|tiny|hard to read|bigger)|can.?t read (the|anything|it)|hard to read|still too small|much bigger|even bigger"),
    ("family_call", r"call (my )?(daughter|son|grand\w*|helper|family|niece|nephew|kid)|(daughter|son|helper|family) to (help|see|look|fix)|"
                    r"show my (daughter|son|helper|family)|helper (see|look|help)|see my screen|help me remotely|remote help|share my screen with"),
    ("help_answer", r"^(how (do|can|should) (i|you|we)|how to)\b(?!.*\b(not|can.?t|won.?t|don.?t|isn.?t|doesn.?t|no|broke|broken|fix|stopped|keeps|problem|wrong)\b)"),
    ("pc_question", r"(make|making|makes|no) (any )?(sound|noise)|froze|no sound|can.?t hear|sound (is |isn.?t |not |stopped|gone)|speaker|volume|muted|no noise|"
                    r"internet|wi-?fi|wifi|online|network|slow|sluggish|frozen|freez|hang(s|ing)|stuck|taskbar|"
                    r"\bfan\b|overheat|too hot|disk (is )?full|drive (is )?full|out of space|storage|space left|health check|battery"),
    ("help_answer", r"^(how (do|can|should) (i|you|we)|how to|where (do|can) i|what (is|are|does)|what.?s the|is there a way|can you (show|tell) me how|teach me|explain)\b"),
]
