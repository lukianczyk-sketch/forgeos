"""forgeos-movingday commands. Exit: 0 done, 1 done but something was left or locked away / not found,
3 wrong use, 4 not enough room, 5 the drive needs its BitLocker key, 6 wrong BitLocker key."""
import os
import sys

from . import gb, run, state_dir
from . import move, passwords, programs, scan, sources, stick

def usage():
    print("usage: forgeos-movingday find | open DEV [--key-stdin] | close DEV | scan FOLDER [--user NAME]\n"
          "       forgeos-movingday move FOLDER --user NAME [--pick Documents,Pictures,...,bookmarks]\n"
          "       forgeos-movingday programs FOLDER --user NAME | passwords FOLDER --user NAME\n"
          "       forgeos-movingday passwords-done [--erase-from FOLDER --user NAME] | pack-stick FOLDER | report",
          file=sys.stderr)
    return 3


def opts(rest):
    """FOLDER --user NAME [--pick LIST] -> (folder, user, pick) or None."""
    if not rest or rest[0].startswith("--"):
        return None
    got = {"--user": None, "--pick": None}
    it = iter(rest[1:])
    for a in it:
        if a not in got:
            return None
        got[a] = next(it, None)
        if got[a] is None:
            return None
    return rest[0], got["--user"], got["--pick"]


def find_cmd():
    rows = sources.find()
    for r in rows:
        print("SOURCE\t" + "\t".join(r) + "\t" + sources.describe(r))
    return 0 if rows else 1


def open_cmd(rest):
    if len(rest) not in (1, 2) or (len(rest) == 2 and rest[1] != "--key-stdin"):
        return usage()
    key = sys.stdin.readline().strip() if len(rest) == 2 else None
    code, where = sources.open_dev(rest[0], key)
    print("OPEN\t%s\t%s" % (rest[0], where) if code == 0 else where)
    return code


def scan_cmd(folder, user):
    if not os.path.isdir(folder):
        print("That folder is not there.")
        return 3
    base = sources.base(folder)
    lines = scan.scan(base, user)
    print("ROOT\t%s\t%s" % (sources.kind(folder), base))
    for line in lines:
        print(line)
    return 0 if lines else 1


def move_cmd(folder, user, pick):
    picks = move.picks_from(pick or "Documents,Pictures,Music,Videos,Desktop,Downloads,bookmarks")
    if picks is None or not user or not os.path.isdir(folder):
        return usage()
    code, lines = move.move(sources.base(folder), user, picks)
    for line in lines:
        if "\t" in line or code == 3:
            print(line)
    if code == 3:
        return code
    text = move.plain(lines)
    for line in text:
        print(line)
    with open(os.path.join(state_dir(), "last-report.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(text) + "\n")
    return code


def passwords_cmd(folder, user):
    base = sources.base(folder)
    files = scan.password_files(base, scan.user_dir(base, user) if user else None)
    if not files:
        print("No saved-password files were found. Export them in each browser on Windows first"
              " (the Moving Box does it with you).")
        return 1
    n, rows = passwords.stage(files)
    run(["wl-copy", passwords.BRAVE_PAGE], 10)
    print("PASSWORDS\t%d\t%d\t%s" % (n, rows, passwords.PASS_DIR))
    print(passwords.how_to(rows))
    return 0 if n else 1


def done_cmd(rest):
    gone = passwords.erase()
    extra = 0
    if rest:
        o = opts(rest[1:]) if rest[0] == "--erase-from" else None
        if not o or not o[1] or o[2]:
            return usage()
        base = sources.base(o[0])
        extra = passwords.erase_source(scan.password_files(base, scan.user_dir(base, o[1])))
    print("ERASED\t%d\t%d" % (gone, extra))
    print("The password file was erased." if gone or extra else "There was no password file left to erase.")
    return 0


def report_cmd():
    try:
        with open(os.path.join(state_dir(), "last-report.txt"), encoding="utf-8") as f:
            print(f.read().rstrip())
        return 0
    except OSError:
        print("Moving Day has not moved anything yet.")
        return 1


def main(args):
    cmd, rest = (args[0], args[1:]) if args else ("", [])
    if cmd == "find" and not rest:
        return find_cmd()
    if cmd == "open":
        return open_cmd(rest)
    if cmd == "close" and len(rest) == 1:
        return 0 if sources.close_dev(rest[0]) == 0 else 1
    if cmd == "passwords-done":
        return done_cmd(rest)
    if cmd == "pack-stick":
        return stick.pack(rest)
    if cmd == "report" and not rest:
        return report_cmd()
    o = opts(rest)
    if cmd == "scan" and o and not o[2]:
        return scan_cmd(o[0], o[1])
    if cmd == "move" and o:
        return move_cmd(*o)
    if cmd == "programs" and o and o[1] and not o[2]:
        base = sources.base(o[0])
        lines = programs.report(base, scan.user_dir(base, o[1]))
        for line in lines:
            print(line)
        return 0 if lines else 1
    if cmd == "passwords" and o and o[1] and not o[2]:
        return passwords_cmd(o[0], o[1])
    if cmd == "free" and not rest:
        print("FREE\t%s" % gb(sources.free_space(os.path.expanduser("~"))))
        return 0
    return usage()
