# shellcheck shell=bash
# Pretend running programs for the Ask Before Connecting tests (Job 24): a pretend /proc ($WORK/proc) and a pretend
# PC ($WORK/root: its /usr and /var/lib/flatpak). Sourced by tests/netask-fakes.sh.
# proc PID [flatpak:ID] [env:NAME] [exe:FILE] -- ARGS...: a pretend running program in the pretend /proc. Its real
# file (/proc/PID/exe) is FILE, else the PC's own file ($WORK/root + ARGS[0]) if there is one, else a file of its own.
proc() {
  local pid="$1" d="$WORK/proc/$1" exe=""; shift
  rm -rf "$d"; mkdir -p "$d/root"; : > "$d/environ"
  while [ $# -gt 0 ] && [ "$1" != -- ]; do
    case "$1" in
      flatpak:*) printf '[Application]\nname=%s\n' "${1#flatpak:}" > "$d/root/.flatpak-info" ;;
      env:*) printf '%s=1\0' "${1#env:}" >> "$d/environ" ;;
      exe:*) exe="${1#exe:}" ;;
    esac
    shift
  done
  shift
  printf '%s\0' "$@" > "$d/cmdline"
  basename "${1:-x}" > "$d/comm"
  if [ -z "$exe" ]; then
    if [ -e "$WORK/root$1" ]; then exe="$WORK/root$1"; else exe="$WORK/exe/$pid"; : > "$exe"; fi
  fi
  ln -s "$exe" "$d/exe"
}
# real PATH...: a file that really is on the pretend PC (in /usr, or in /var/lib/flatpak/app/ID/current/active/files)
real() { local f; for f in "$@"; do mkdir -p "$(dirname "$WORK/root$f")"; : > "$WORK/root$f"; done; }
flatpak_app() { real "/var/lib/flatpak/app/$1/current/active/files/$2"; echo "exe:$WORK/root/var/lib/flatpak/app/$1/current/active/files/$2"; }
