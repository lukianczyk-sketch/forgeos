"""What the window and Forge Helper show: 'status' (TAB-separated lines for the window) and 'report'
(plain English). Neither ever shows a password or a code."""
import os
import shutil

from . import DAY, OLD_AFTER, SEVEN, day, draft, now, read_state, unlock, words


def envelope_age(st):
    return int((now() - st["made"]) // DAY) if st.get("made") else -1


def ready(d):
    """("yes", "") when an envelope can be made, else ("no", why)."""
    if not d["people"]:
        return "no", "Add at least one trusted person first."
    if not words.ok():
        return "no", "The word list for the codes is missing."
    if not shutil.which(SEVEN):
        return "no", "7-Zip is missing."
    return "yes", ""


def status():
    d, st = draft.load(), read_state()
    rows = [("PEOPLE", str(len(d["people"])), ", ".join(draft.person_names(d)))]
    rows += [("PERSON", p["name"], p.get("phone") or "-") for p in d["people"]]
    for acc_id, a in sorted(d["accounts"].items()):
        rows.append(("ACCOUNT", acc_id, draft.account_name(d, acc_id), a.get("plan", ""), a.get("who") or "-",
                     a.get("note") or "-"))
    rows.append(("SAFE", d["safe"] or "-"))
    rows += [("FOLDER", f) for f in d["folders"]]
    rows += [("LETTER", n) for n in sorted(d["letters"])]
    rows.append(("NOTE", "yes" if d["note"] else "no"))
    for item, company, url, what in draft.legacy_list():
        rows.append(("LEGACY", item, company, url, "done" if item in d["legacy"] else "todo", what))
    if st.get("made"):
        rows.append(("ENVELOPE", day(st["made"]), str(envelope_age(st)), st.get("name", "-")))
        rows += [("WHERE", p) for p in st.get("paths", [])]
        rows += [("HOLDER", h[0], h[1]) for h in st.get("holders", []) if len(h) == 2]
        rows.append(("UNLOCKIN", "yes" if st.get("unlock") else "no"))
    else:
        rows.append(("ENVELOPE", "-", "-", "-"))
    rows.append(("UNLOCK", unlock.status()))
    rows.append(("READY",) + ready(d))
    for r in rows:
        print("\t".join(str(x).replace("\t", " ").replace("\n", " ") for x in r))
    return 0


def report():
    d, st = draft.load(), read_state()
    out = ["Digital Will - if something happens to you, the people you picked can get into this PC, your accounts and your photos."]
    if not d["people"] and not st.get("made"):
        out.append("You have not set it up yet. Open Digital Will from the menu: answer a few questions, then make your Emergency Envelope (a locked file on a USB stick plus a printed letter).")
        print("\n".join(out))
        return 1
    out.append("Trusted people: %s." % (", ".join(draft.person_names(d)) or "none yet"))
    out.append("Accounts listed: %d. Letters written: %d. Folders to keep: %d." % (len(d["accounts"]), len(d["letters"]), len(d["folders"])))
    out.append("Password safe: %s." % (os.path.basename(d["safe"]) if d["safe"] else "not picked"))
    if st.get("made"):
        age = envelope_age(st)
        out.append("Emergency Envelope made %s (%d days ago)%s." % (day(st["made"]), age, ", on a USB stick too" if len(st.get("paths", [])) > 1 else ""))
        out.append("Opening code: %s." % ("two-key lock - " + " and ".join(h[1] for h in st.get("holders", [])) if st.get("two")
                                          else "with " + (st.get("holders") or [["", "your trusted person"]])[0][1]))
        if now() - st["made"] >= OLD_AFTER:
            out.append("It is more than 6 months old: please make a new envelope.")
    else:
        out.append("No Emergency Envelope made yet - press \"Make my Emergency Envelope\".")
    u = unlock.status()
    out.append({"no-luks": "This PC's drive is not locked, so your family only needs your sign-in password.",
                "added": "PC unlock for family: added.",
                "not-added": "PC unlock for family: NOT added yet - without it your family can never open this PC's locked drive."}[u])
    todo = [c for i, c, _u, _w in draft.legacy_list() if i not in d["legacy"]]
    out.append("Company checklist: %s." % ("all done" if not todo else "still to do - " + ", ".join(todo)))
    print("\n".join(out))
    return 0 if st.get("made") and now() - st["made"] < OLD_AFTER else 1
