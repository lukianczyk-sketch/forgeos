"""ForgeOS Find Anything (Job 11): the private search list (SQLite). Only this user can read it."""
import os
import sqlite3
import time

from findlib.words import clean_words, day, snip


def db_path():
    base = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
    return os.path.join(base, "forgeos", "find", "index.db")


def has_fts(con):
    if os.environ.get("FORGEOS_FIND_NO_FTS") == "1":
        return False
    try:
        con.execute("CREATE VIRTUAL TABLE temp.probe USING fts5(x)")
        con.execute("DROP TABLE temp.probe")
        return True
    except sqlite3.Error:
        return False


class Store:
    def __init__(self, path=None):
        self.path = path or db_path()
        folder = os.path.dirname(self.path)
        os.makedirs(folder, mode=0o700, exist_ok=True)
        os.chmod(folder, 0o700)
        old = os.umask(0o077)
        try:
            self.con = sqlite3.connect(self.path, timeout=30)
        finally:
            os.umask(old)
        os.chmod(self.path, 0o600)
        self.fts = has_fts(self.con)
        c = self.con
        c.execute("CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY, value TEXT)")
        c.execute("CREATE TABLE IF NOT EXISTS files(path TEXT PRIMARY KEY, mtime INTEGER,"
                  " size INTEGER, kind TEXT, indexed INTEGER)")
        if self.fts:
            c.execute("CREATE VIRTUAL TABLE IF NOT EXISTS docs USING fts5(path UNINDEXED, name, body,"
                      " tokenize='porter unicode61 remove_diacritics 2')")
        else:
            c.execute("CREATE TABLE IF NOT EXISTS docs_plain(path TEXT PRIMARY KEY, name TEXT, body TEXT)")
        mode = "fts5" if self.fts else "plain"
        if self.get("mode") != mode:  # search type changed: read all again
            self.clear()
            self.set("mode", mode)
        c.commit()

    def get(self, key, default=None):
        row = self.con.execute("SELECT value FROM meta WHERE key = ?", (key,)).fetchone()
        return row[0] if row else default

    def set(self, key, value):
        self.con.execute("INSERT OR REPLACE INTO meta VALUES (?, ?)", (key, str(value)))

    def table(self):
        return "docs" if self.fts else "docs_plain"

    def clear(self):
        self.con.execute("DELETE FROM files")
        self.con.execute("DELETE FROM " + self.table())

    def known(self):
        return {p: (m, s) for p, m, s in self.con.execute("SELECT path, mtime, size FROM files")}

    def put(self, path, mtime, size, kind, name, body):
        self.drop(path)
        self.con.execute("INSERT INTO files VALUES (?, ?, ?, ?, ?)", (path, mtime, size, kind, int(time.time())))
        self.con.execute("INSERT INTO " + self.table() + " (path, name, body) VALUES (?, ?, ?)", (path, name, body))

    def drop(self, path):
        self.con.execute("DELETE FROM files WHERE path = ?", (path,))
        self.con.execute("DELETE FROM " + self.table() + " WHERE path = ?", (path,))

    def paths_under(self, path):
        top = path.rstrip("/") + "/"
        return [p for (p,) in self.con.execute("SELECT path FROM files") if p == path or p.startswith(top)]

    def count(self):
        return self.con.execute("SELECT count(*) FROM files").fetchone()[0]

    def commit(self):
        self.con.commit()

    def search(self, words, kind="any", after="", before="", limit=20, any_word=False):
        """Best first: [(path, kind, mtime, snippet)]. A name hit counts 5x."""
        words = clean_words(words)
        if not words:
            return []
        lo, hi = day(after) or 0, day(before, True) or 4102444800
        if self.fts:
            query = (" OR " if any_word else " AND ").join('"%s"' % w for w in words)
            sql = ("SELECT docs.path, f.kind, f.mtime, snippet(docs, 2, '[', ']', '...', 12)"
                   " FROM docs JOIN files f ON f.path = docs.path WHERE docs MATCH ?"
                   " AND (? = 'any' OR f.kind = ?) AND f.mtime BETWEEN ? AND ?"
                   " ORDER BY bm25(docs, 0, 5, 1), f.mtime DESC LIMIT ?")
            return self.con.execute(sql, (query, kind, kind, lo, hi, limit)).fetchall()
        return self.plain_search(words, kind, lo, hi, limit, any_word)

    def plain_search(self, words, kind, lo, hi, limit, any_word):
        """No FTS5: LIKE on name + words, same scoring (name 5x)."""
        test = " OR ".join(["(lower(d.name) LIKE ? OR lower(d.body) LIKE ?)"] * len(words))
        args = [a for w in words for a in ("%" + w + "%", "%" + w + "%")]
        sql = ("SELECT d.path, f.kind, f.mtime, lower(d.name), d.body FROM docs_plain d"
               " JOIN files f ON f.path = d.path WHERE (" + test + ")"
               " AND (? = 'any' OR f.kind = ?) AND f.mtime BETWEEN ? AND ? LIMIT 5000")
        found = []
        for path, k, mtime, name, body in self.con.execute(sql, args + [kind, kind, lo, hi]):
            low = body.lower()
            if not any_word and not all(w in name or w in low for w in words):
                continue
            score = sum(5 for w in words if w in name) + sum(1 for w in words if w in low)
            found.append((-score, -mtime, path, k, mtime, snip(body, low, words)))
        found.sort()
        return [(p, k, m, s) for _, _, p, k, m, s in found[:limit]]
