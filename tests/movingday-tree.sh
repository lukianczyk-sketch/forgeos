# shellcheck shell=bash
# The fake Windows drive for the Moving Day tests (Job 14). Sourced by tests/movingday-fakes.sh.
# win_tree DIR: a Windows drive with user Robert (files, OneDrive, junk, a password export, Chrome + Firefox
# bookmarks, Start menu), plus the users Public and Default that must be left out.
win_tree() {
  local d="$1" u="$1/Users/Robert" sm="$1/ProgramData/Microsoft/Windows/Start Menu/Programs"
  mkdir -p "$d/Windows/System32" "$d/Users/Public/Documents" "$d/Users/Default/Documents" "$u/Documents/Taxes" "$u/Pictures" \
    "$u/OneDrive/Documents" "$u/Downloads" "$u/Desktop" "$u/Music" "$u/AppData/Local/Google/Chrome/User Data/Default" \
    "$u/AppData/Roaming/Mozilla/Firefox/Profiles/ab12.default-release" "$sm/Windows Accessories" "$sm/Mozilla Firefox"
  echo "tax 2023" > "$u/Documents/Taxes/2023.pdf"; echo "letter" > "$u/Documents/letter.docx"
  echo "x" > "$u/Documents/desktop.ini"; echo "lock" > "$u/Documents/~\$letter.docx"; echo "od" > "$u/OneDrive/Documents/notes.txt"
  echo "cat" > "$u/Pictures/cat.jpg"; echo "lnk" > "$u/Desktop/Word.lnk"; echo "song" > "$u/Music/song.mp3"
  echo "setup" > "$u/Downloads/setup.exe"; ln -s ../Music "$u/Documents/My Music"
  printf 'name,url,username,password,note\nbank,https://bank.example,rob,secret1,\nmail,https://mail.example,rob,secret2,\n' > "$u/Downloads/Chrome Passwords.csv"
  echo "public" > "$d/Users/Public/Documents/p.txt"
  cat > "$u/AppData/Local/Google/Chrome/User Data/Default/Bookmarks" <<'EOF'
{"checksum": "x", "roots": {"bookmark_bar": {"children": [{"name": "Kern County", "type": "url", "url": "https://www.kerncounty.com/"},
 {"name": "News", "type": "folder", "children": [{"name": "KGET", "type": "url", "url": "https://www.kget.com/"},
 {"name": "bad", "type": "url", "url": "javascript:alert(1)"}]}], "name": "Bookmarks bar", "type": "folder"},
 "other": {"children": [], "type": "folder", "name": "Other"}, "synced": {"children": [], "type": "folder", "name": "Mobile"}}, "version": 1}
EOF
  python3 - "$u/AppData/Roaming/Mozilla/Firefox/Profiles/ab12.default-release/places.sqlite" <<'EOF'
import sqlite3, sys
db = sqlite3.connect(sys.argv[1])
db.executescript("""CREATE TABLE moz_places(id INTEGER PRIMARY KEY, url TEXT, title TEXT);
CREATE TABLE moz_bookmarks(id INTEGER PRIMARY KEY, type INT, fk INT, parent INT, position INT, title TEXT, guid TEXT);
INSERT INTO moz_bookmarks VALUES(1,2,NULL,0,0,'','root________'),(2,2,NULL,1,0,'menu','menu________'),
 (3,2,NULL,1,1,'toolbar','toolbar_____'),(4,2,NULL,1,2,'tags','tags________'),(10,1,1,3,0,'Weather','a1'),(11,1,2,3,1,'Most','a2');
INSERT INTO moz_places VALUES(1,'https://www.weather.gov/','Weather'),(2,'place:sort=8','Most visited');""")
db.commit()
EOF
  touch "$sm/Windows Accessories/Notepad.lnk" "$sm/Mozilla Firefox/Firefox.lnk" "$sm/Excel.lnk" "$sm/Uninstall Foo.lnk" "$sm/Some Odd Tool.lnk"
}
