#!/usr/bin/env bash
# ── test-material-fallback.sh ─────────────────────────────────────────────────
# scripts/material-fallback.sh against a fake awww / awww-daemon in a scratch PATH and cache:
# what it starts, what it sends, and that it never kills a daemon it did not start.
#
#     bash scripts/test-material-fallback.sh
#
# Safe: nothing real is run or touched.
# ─────────────────────────────────────────────────────────────────────────────
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="$here/material-fallback.sh"
pass=0; fail=0
check() { if [[ "$2" == "$3" ]]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL $1"; echo "  got:  $2"; echo "  want: $3"; fi; }

scratch="$(mktemp -d)"; trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/bin" "$scratch/cache"
log="$scratch/calls"; up="$scratch/daemon-up"
# The fakes: awww-daemon "starts" by creating the flag; awww query succeeds only while it exists.
cat > "$scratch/bin/awww-daemon" <<FAKE
#!/usr/bin/env bash
echo "awww-daemon \$*" >> "$log"; : > "$up"
FAKE
cat > "$scratch/bin/awww" <<FAKE
#!/usr/bin/env bash
echo "awww \$*" >> "$log"
case "\$1" in
    query) [[ -e "$up" ]] ;;
    kill)  rm -f "$up" ;;
    *)     [[ -e "$up" ]] ;;
esac
FAKE
chmod +x "$scratch/bin/"*
png="$scratch/a.png"; : > "$png"
run() { env PATH="$scratch/bin:/usr/bin:/bin" XDG_CACHE_HOME="$scratch/cache" bash "$script" "$@"; }

# ── no daemon yet: it starts one, says so, and sends the picture ──
out="$(run set DP-1 "$png")"; code=$?
check "first set: exit 0" "$code" "0"
check "first set: says started" "$out" "started"
check "first set: the daemon was started" "$(grep -c '^awww-daemon' "$log")" "1"
check "first set: sent to that output, no transition" "$(grep '^awww img' "$log")" "awww img $png --outputs DP-1 --transition-type none"
check "first set: marks it as ours" "$([[ -e $scratch/cache/quickshell-quicktest/material/daemon-started-by-shell ]] && echo yes)" "yes"

# ── daemon already up: just sends, starts nothing, says nothing ──
: > "$log"
out="$(run set HDMI-A-1 "$png")"; code=$?
check "second set: exit 0" "$code" "0"
check "second set: silent" "$out" ""
check "second set: no second daemon" "$(grep -c '^awww-daemon' "$log")" "0"

# ── errors ──
check "missing file: exit 2" "$(run set DP-1 "$scratch/none.png" >/dev/null; echo $?)" "2"
check "no output named: exit 2" "$(run set "" "$png" >/dev/null; echo $?)" "2"
check "no awww at all: exit 3" "$(env PATH=/nonexistent XDG_CACHE_HOME="$scratch/cache" /bin/bash "$script" set DP-1 "$png" >/dev/null; echo $?)" "3"
check "no subcommand: exit 64" "$(run >/dev/null 2>&1; echo $?)" "64"

# ── clear: kills only a daemon it started ──
: > "$log"
run clear
check "clear: kills the one it started" "$(grep -c '^awww kill' "$log")" "1"
check "clear: forgets it" "$([[ -e $scratch/cache/quickshell-quicktest/material/daemon-started-by-shell ]] && echo yes || echo no)" "no"
: > "$up"; : > "$log"
run clear
check "clear: leaves a daemon it did not start alone" "$(grep -c '^awww kill' "$log")" "0"

echo "$pass passed, $fail failed"
exit $((fail ? 1 : 0))
