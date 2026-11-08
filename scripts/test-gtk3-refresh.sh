#!/usr/bin/env bash
# ── test-gtk3-refresh.sh ──────────────────────────────────────────────────────
# wave-lib.sh's gtk3_refresh against a stub `gsettings`: it flips the gtk-theme key to another theme and back so
# open GTK apps re-read their CSS, and it must always END on the user's theme — including when two refreshes
# overlap (the second used to read the first's temporary value as the user's theme and keep it) or one was killed
# halfway. Safe: the stub keeps its value in a temp file; the real settings are never touched.
#
#     bash scripts/test-gtk3-refresh.sh [path/to/wave-lib.sh]     (default: the repo's)
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
LIB="${1:-$HERE/wave-lib.sh}"
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "  FAIL  $1"; echo "        got  [$2]"; echo "        want [$3]"; fi; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/state" "$T/run" "$T/cache/wal-stage"
export PATH="$T/bin:$PATH" XDG_STATE_HOME="$T/state" XDG_RUNTIME_DIR="$T/run" HOME="$T/home"
# A gsettings whose `set` takes a moment, so two overlapping refreshes really do overlap.
cat > "$T/bin/gsettings" <<'STUB'
#!/usr/bin/env bash
V="$STUB_VALUE"
case "$1" in
    get) printf "'%s'\n" "$(cat "$V")" ;;
    set) sleep 0.05; printf '%s' "$4" > "$V" ;;
esac
STUB
chmod +x "$T/bin/gsettings"
export STUB_VALUE="$T/value"

CACHE="$T/cache"; WAL_CACHE="$T/cache"; LOG="$T/log"; SHELL_DIR="$HERE/.."; : > "$LOG"
have() { command -v "$1" >/dev/null 2>&1; }
step() { :; }; skip() { :; }
# shellcheck disable=SC1090
source "$LIB" >/dev/null 2>&1
STAGE="$T/cache/wal-stage"

run_one()  { gtk3_refresh >/dev/null 2>&1; }

printf '%s' "adw-gtk3-dark" > "$STUB_VALUE"
run_one
ok "one refresh ends on the user's theme" "$(cat "$STUB_VALUE")" "adw-gtk3-dark"
ok "it leaves no record behind" "$([ -e "$T/state/quicktest-gtk-theme-real" ] && echo yes || echo no)" "no"

printf '%s' "adw-gtk3-dark" > "$STUB_VALUE"
# The second and third start while the first is between its two writes (the 0.25 s nap), like two colour changes close together.
run_one & sleep 0.12; run_one & sleep 0.05; run_one & wait
ok "three overlapping refreshes still end on the user's theme" "$(cat "$STUB_VALUE")" "adw-gtk3-dark"

printf '%s' "Adwaita-dark" > "$STUB_VALUE"
run_one & sleep 0.12; run_one & wait
ok "a user who really uses Adwaita-dark keeps it" "$(cat "$STUB_VALUE")" "Adwaita-dark"

# A refresh killed between its two writes leaves the temporary value in the key and the real one on record.
printf '%s' "Adwaita-dark" > "$STUB_VALUE"; printf '%s\n' "adw-gtk3-dark" > "$T/state/quicktest-gtk-theme-real"
run_one
ok "an interrupted toggle is undone by the next refresh" "$(cat "$STUB_VALUE")" "adw-gtk3-dark"
ok "and the record is cleared" "$([ -e "$T/state/quicktest-gtk-theme-real" ] && echo yes || echo no)" "no"

printf '%s' "" > "$STUB_VALUE"; run_one
ok "an unreadable theme is left alone, not written as empty" "$(cat "$STUB_VALUE")" ""

echo; echo "$pass passed, $fail failed"; [ "$fail" = 0 ]
