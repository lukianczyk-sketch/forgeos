#!/usr/bin/env bash
# Tests for Ask Before Connecting (Job 24), case F: the files are all there and clean, the build script (pinned
# OpenSnitch + its SHA-256, ForgeOS's settings), the system rule, ForgeOS's own apps list, the service and menu
# entry. (The recipe, protocol, Forge Helper, Report Card and CI: tests/test-netask-hooks.sh.)
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-netask-files.sh <repo-root>
set -u
ROOT="$(cd "${1:-.}" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
SYS="$ROOT/files/system"; LIB="$SYS/usr/lib/forgeos-netask/netlib"; SH="$SYS/usr/share/forgeos/netask"
HL="$SYS/usr/lib/forgeos-helper"; SETUP="$ROOT/files/scripts/forgeos-setup.sh"; INST="$ROOT/files/scripts/install-opensnitch.sh"
D="$SYS/usr/share/applications/forgeos-netask.desktop"; SVC="$SYS/usr/lib/systemd/system/forgeos-netask.service"
HELP="$SYS/usr/share/forgeos/helper/help/ask-before-connecting.md"; T=$'\t'
mkdir -p "$WORK/bin"; export PATH="$WORK/bin:$PATH" PYTHONDONTWRITEBYTECODE=1
EXE=("$SYS/usr/bin/forgeos-netask" "$SYS/usr/bin/forgeos-netask-gui" "$SYS/usr/libexec/forgeos-netask-service")

check F1 'grep -qx "chmod 0755 /usr/bin/forgeos-netask /usr/bin/forgeos-netask-gui /usr/libexec/forgeos-netask-service" "$SETUP" && grep -qx "systemctl enable opensnitch.service forgeos-netask.service" "$SETUP" && for f in "${EXE[@]}"; do [ -x "$f" ] || exit 1; done'
check F2 'python3 -c "import ast, sys; [ast.parse(open(f).read(), f, feature_version=(3, 10)) for f in sys.argv[1:]]" "$LIB"/*.py "${EXE[0]}" "${EXE[2]}" && [ "$(ls "$LIB" | tr "\n" " ")" = "__init__.py askui.py cli.py decide.py dialog.py explain.py flatpak.py history.py later.py names.py proc.py requests.py server.py service.py store.py trust.py who.py " ]'
check F3 '(for f in "${EXE[@]}" "$LIB"/*.py "$SH"/* "$SH"/rules/* "$D" "$SVC" "$HELP" "$INST" "$ROOT"/tests/*netask*; do [ -f "$f" ] || continue; [ "$(wc -c < "$f")" -lt 6400 ] && ! grep -q $'"'"'\r'"'"' "$f" && ! grep -q $'"'"'\t'"'"' "$f" && [ -z "$(tail -c 1 "$f")" ] || { echo "  not clean: $f"; exit 1; }; done)'
check F4b 'grep -qx "kernel.yama.ptrace_scope = 1" "$SYS/usr/lib/sysctl.d/60-forgeos-netask.conf" && grep -qx "RestartSec=3" "$SYS/usr/lib/systemd/system/opensnitch.service.d/forgeos.conf" && grep -qx "After=forgeos-netask.service" "$SYS/usr/lib/systemd/system/opensnitch.service.d/forgeos.conf"'
check F4 'grep -qx "Exec=/usr/bin/forgeos-netask-gui" "$D" && grep -qx "Name=Who Uses the Internet" "$D" && { ! command -v desktop-file-validate >/dev/null || desktop-file-validate "$D"; } && grep -qx "ExecStart=/usr/libexec/forgeos-netask-service" "$SVC" && grep -qx "WantedBy=multi-user.target" "$SVC" && grep -qx "Restart=always" "$SVC" && head -n 1 "$HELP" | grep -qx "# Ask Before Connecting: which programs may use the internet"'
# F5: the build script: OpenSnitch 1.8.0 from GitHub, a fixed SHA-256 checked, no package scripts; ForgeOS's settings
check F5 'grep -qx "OSN_VERSION=\"1.8.0\"" "$INST" && grep -qx "OSN_SHA256=\"e06e9119daf764e56455b61c319e496274c0274bb53bb94a0ff1ab72967fea7d\"" "$INST" && grep -q "https://github.com/evilsocket/opensnitch/releases/download/v\${OSN_VERSION}/\${OSN_FILE}" "$INST" && grep -q "sha256sum --check" "$INST" && grep -q "tsflags=noscripts" "$INST" && grep -q "grpc_tools.protoc" "$INST"'
mkdir -p "$WORK/etc"; printf '%s\n' '{"Server": {"Address": "unix:///tmp/osui.sock", "LogFile": "/var/log/opensnitchd.log"}, "DefaultAction": "allow", "DefaultDuration": "once", "InterceptUnknown": false, "ProcMonitorMethod": "ebpf", "Firewall": "nftables", "Rules": {"Path": "/etc/opensnitchd/rules/", "EnableChecksums": false}}' > "$WORK/etc/default-config.json"
FORGEOS_OSN_ETC="$WORK/etc" FORGEOS_OSN_SHARE="$SH" bash "$INST" configure; CODE=$?
check F6 '[ "$CODE" = 0 ] && jq -e ".DefaultAction == \"deny\" and .Server.Address == \"unix:///run/forgeos-netask/osui.sock\" and .Rules.EnableChecksums == true and .Firewall == \"nftables\" and .Server.LogFile == \"/var/log/opensnitchd.log\"" "$WORK/etc/default-config.json" > /dev/null && [ -f "$WORK/etc/rules/001-forgeos-system.json" ]'
# F7: the system rule: system users (not people) running programs from the read-only /usr, always allowed
check F7 'python3 - "$SH/rules/001-forgeos-system.json" <<'"'"'PY'"'"'
import json, re, sys
r = json.load(open(sys.argv[1])); ops = {o["operand"]: o for o in r["operator"]["list"]}
uid, path = re.compile(ops["user.id"]["data"]), re.compile(ops["process.path"]["data"])
assert r["name"] == "001-forgeos-system" and r["action"] == "allow" and r["duration"] == "always" and r["operator"]["type"] == "list"
assert all(uid.match(u) for u in ("0", "81", "999", "65534")) and not any(uid.match(u) for u in ("1000", "1001", "4200"))
assert path.match("/usr/sbin/NetworkManager") and not path.match("/home/me/usr/x") and not path.match("/tmp/usr/")
PY'
# F8: ForgeOS's own apps (never asked) = the recipe's default Flatpaks, except RustDesk (a remote-control app)
WANT="$(sed -n '/default-flatpaks/,/scope: user/p' "$ROOT/recipes/common-modules.yml" | grep -oE "^ +- [A-Za-z0-9._-]+\.[A-Za-z0-9._-]+" | sed 's/^ *- //' | grep -vx com.rustdesk.RustDesk | sort)"
check F8 '[ "$(grep -v "^#" "$SH/trusted-apps.txt" | sort)" = "$WANT" ] && [ "$(wc -l <<< "$WANT")" -ge 20 ] && ! grep -v "^#" "$SH/trusted-apps.txt" | grep -qi rustdesk'

echo
if [ "$failures" -eq 0 ]; then echo "All Ask Before Connecting tests F passed."; else echo "$failures test(s) failed."; fi
exit "$((failures > 0))"
