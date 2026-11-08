"""The envelope's pages (web pages, so they print well): "Open me first" INSIDE the locked envelope (it has
the passwords) and the "Letter to my family" OUTSIDE it (no secrets). The code cards are in cards.py."""
from . import draft, esc, full_name, nice_day, user

STYLE = ("<style>body{font-family:sans-serif;font-size:14pt;max-width:46em;margin:2em auto;line-height:1.45}"
         "h1{font-size:22pt}h2{font-size:17pt;margin-top:1.4em;border-bottom:2px solid #444}"
         "td,th{border:1px solid #888;padding:.3em .5em;text-align:left;vertical-align:top}table{border-collapse:collapse}"
         ".code{font-family:monospace;font-size:20pt;font-weight:bold;letter-spacing:.05em}"
         ".card{border:3px dashed #444;padding:1em 1.5em;margin:1.5em 0;page-break-inside:avoid}</style>")
NOT_LEGAL = ("This is not a legal will. Please also have a real will (a lawyer, or your state's own will form) "
             "that says who gets your things.")


def page(title, body):
    return ('<!doctype html><html><head><meta charset="utf-8"><title>%s</title>%s</head><body>%s</body></html>\n'
            % (esc(title), STYLE, body))


def people_list(d):
    rows = "".join("<li>%s%s</li>" % (esc(p["name"]), " - " + esc(p["phone"]) if p.get("phone") else "")
                   for p in d["people"])
    return "<ul>%s</ul>" % rows


def pre(text):
    return '<pre style="white-space:pre-wrap;font-size:13pt">%s</pre>' % esc(text)


def inside(d, sec, unlock, made):
    """'Open me first.html' - inside the envelope. sec: login, safe, extra (may be empty)."""
    who = full_name()
    b = "<h1>%s's Emergency Envelope</h1><p>Made %s. If you are reading this, I wanted you to be able to take care of things. Thank you.</p>" % (esc(who), esc(nice_day(made)))
    b += "<h2>My trusted people</h2>" + people_list(d)
    b += "<h2>1. Getting into my computer</h2><ol>"
    if unlock:
        b += '<li>Turn it on. When it asks for the disk password, type the PC unlock code:<br><span class="code">%s</span></li>' % esc(unlock)
    else:
        b += "<li>Turn it on. (If it asks for a disk password, it is the one I use when the PC starts.)</li>"
    b += "<li>Sign in as <b>%s</b>" % esc(user())
    b += (' with this password: <span class="code">%s</span></li>' % esc(sec["login"])) if sec.get("login") else " (I did not put the password here).</li>"
    b += "<li>My saved website passwords in the Brave browser open once you are signed in.</li></ol>"
    b += "<h2>2. My passwords</h2>"
    if d["safe"]:
        b += ('<p>My password safe is in the folder <b>Password safe</b> next to this page. Open it with the free '
              'program KeePassXC (keepassxc.org). Its master password: <span class="code">%s</span></p>' % esc(sec.get("safe") or "(not written here)"))
    b += ("<p>Other passwords and PINs:</p>" + pre(sec["extra"])) if sec.get("extra") else ""
    b += "<h2>3. My accounts and what should happen to each</h2>"
    if d["accounts"]:
        b += "<table><tr><th>Account</th><th>What should happen</th><th>Notes</th></tr>"
        for acc_id, a in sorted(d["accounts"].items(), key=lambda kv: draft.account_name(d, kv[0]).lower()):
            plan = draft.PLANS.get(a.get("plan"), "")
            plan += (" " + a["who"]) if a.get("plan") == "give" and a.get("who") else ""
            b += "<tr><td>%s</td><td>%s</td><td>%s</td></tr>" % (esc(draft.account_name(d, acc_id)), esc(plan), esc(a.get("note", "")))
        b += "</table>"
    else:
        b += "<p>(No accounts listed.)</p>"
    b += ("<h2>4. A note from me</h2>" + pre(d["note"])) if d["note"] else ""
    if d["letters"]:
        b += "<h2>5. Letters</h2><p>Each letter is also in the folder <b>Letters</b>.</p>"
        b += "".join("<h3>For %s</h3>%s" % (esc(n), pre(t)) for n, t in sorted(d["letters"].items()))
    if d["folders"]:
        b += "<h2>6. Folders I kept for you</h2><p>They are in the folder <b>Kept folders</b> next to this page.</p>"
    return page("Open me first", b + "<h2>Please note</h2><p>%s</p>" % NOT_LEGAL)


def outside(d, made, file_name, holders):
    """'Letter to my family.html' - next to the envelope, no secrets. holders: [(label, name)]."""
    who = full_name()
    b = "<h1>Letter to my family</h1><p>From %s, %s.</p>" % (esc(who), esc(nice_day(made)))
    b += ("<p>Next to this letter is my <b>Emergency Envelope</b>, the locked file <b>%s</b>. It has what you need to get into my "
          "computer and my accounts, my passwords, my wishes and my letters to you. It is locked so only you can open it.</p>" % esc(file_name))
    b += "<h2>The opening code</h2>"
    if len(holders) == 2:
        b += "<p>It takes <b>two</b> people. The code has two halves:</p><ul>"
        b += "".join("<li>%s: %s</li>" % (esc(label), esc(name)) for label, name in holders)
        b += "</ul><p>Type Half A, one space, then Half B.</p>"
    else:
        b += "<p>%s has the opening code on a code card.</p>" % esc(holders[0][1] if holders else "One of my trusted people")
    b += ("<h2>How to open it</h2><ul><li>Windows: install the free 7-Zip (7-zip.org). Right-click the file, 7-Zip, Extract Here, type the code.</li>"
          "<li>Mac: install the free Keka (keka.io) and open the file with it.</li>"
          "<li>ForgeOS or Linux: double-click the file.</li></ul>"
          "<p>Then open <b>Open me first</b>. If there are several envelopes, use the one with the newest date.</p>")
    b += "<h2>My trusted people</h2>" + people_list(d)
    return page("Letter to my family", b + "<h2>Please note</h2><p>%s</p>" % NOT_LEGAL)

