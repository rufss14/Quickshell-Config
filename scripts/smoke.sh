#!/usr/bin/env bash
# ── smoke.sh ──────────────────────────────────────────────────────────────────
# The transient-load check (CLAUDE.md "Checking your work", steps 3 and 4) as one
# command: start a throwaway shell from this directory, wait for it to settle, scan
# its log for the hard load failures a syntax sweep passes clean, confirm the eager
# singletons built their IPC targets, open and close the overview, and scan again.
#
#     bash scripts/smoke.sh              ~25s, exits non-zero on any failure
#     bash scripts/smoke.sh --alongside  run even though a shell is already running
#
# It LAUNCHES QUICKSHELL, so run it deliberately — it is not part of check-all.sh.
# It addresses its instance by --pid, never by config name, so it cannot talk to a
# shell you already have running.
#
# A pass means "it starts and the overview's delegates build without a TypeError",
# NOT "it looks right" — a reload by you is still the visual test.
#
# QS_SMOKE_SHOTS=<dir>: also save a screenshot (grim) of the desktop, the overview, every
# bar panel and every settings page there, for a human — or Claude — to look at.
#
# It refuses while a shell is running: the two would share the notification server,
# port 47821, the cava config and the helpers' lock files, and the throwaway's cleanup
# would pull files out from under the live one. Stop the shell first (or pass
# --alongside, accepting that `bind failed` is then expected and only warned about).
# ─────────────────────────────────────────────────────────────────────────────
set -u
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
shell_dir=$PWD

command -v quickshell >/dev/null || { echo "smoke: quickshell not installed" >&2; exit 2; }

log=$(mktemp --suffix=.qs.log)
shots=${QS_SMOKE_SHOTS:-}
if [ -n "$shots" ]; then
    command -v grim >/dev/null || { echo "smoke: QS_SMOKE_SHOTS needs grim" >&2; exit 2; }
    mkdir -p "$shots"
fi
shot() { [ -n "$shots" ] && grim "$shots/$1.png" 2>/dev/null; }
fails=(); warns=()
fail() { fails+=("$1"); printf '  FAIL  %s\n' "$1"; }
ok()   { printf '  ok    %s\n' "$1"; }
warn() { warns+=("$1"); printf '  warn  %s\n' "$1"; }

# Same variables the real launch sources, so this loads the way a reload does.
# shellcheck disable=SC1091
source scripts/shell-env.sh

live=$(pgrep -x qs; pgrep -x quickshell)
if [ -n "$live" ]; then
    if [ "${1:-}" = "--alongside" ]; then
        warn "a shell is already running (pid $(echo $live | tr '\n' ' ')) — port/notification conflicts are expected"
    else
        echo "smoke: a shell is already running (pid $(echo $live | tr '\n' ' '))." >&2
        echo "       Stop it first, or pass --alongside (see the header)." >&2
        exit 2
    fi
fi

# Its own session, so the cleanup below takes the whole group: quickshell does not
# handle SIGTERM, which orphans its children (spotify-bridge, cava, helpers).
setsid timeout 140 quickshell -p "$shell_dir" >"$log" 2>&1 &
pid=$!
cleanup() { kill -TERM -- "-$pid" 2>/dev/null; sleep 1; kill -KILL -- "-$pid" 2>/dev/null; }
trap cleanup EXIT

# Wait for the load to finish rather than sleeping a fixed time; give up after 20s.
for _ in $(seq 40); do
    grep -q 'Configuration Loaded' "$log" && break
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.5
done
sleep 4   # lazy things (Loaders, the MPRIS player turning up) arrive after "Loaded"

# $pid is `timeout`'s, not quickshell's — `qs ipc --pid` needs the shell itself, or it
# finds no socket and every call below fails. Same group (setsid), so look it up there.
qspid=$(pgrep -g "$pid" -x quickshell | head -1)

echo "── load"
if ! kill -0 "$pid" 2>/dev/null; then
    fail "the shell exited during startup (crash or load failure)"
elif grep -q 'Configuration Loaded' "$log"; then
    ok "Configuration Loaded"
else
    fail "no 'Configuration Loaded' within 20s"
fi

# The hard-failure patterns from CLAUDE.md step 3, plus the ones it names elsewhere.
hard='unavailable|cannot assign|set multiple|not a type|is not defined|illegally masks|FINAL property|read-only property|Could not attach Keys'
if hits=$(grep -iE "$hard" "$log"); then
    fail "hard load failure in the log:"; echo "$hits" | head -10 | sed 's/^/        /'
else
    ok "no hard load failures"
fi
if grep -q 'bind failed' "$log"; then
    if [ -n "$live" ]; then warn "bind failed (expected: another shell holds the port)"
    else fail "bind failed with no other shell running — a stray spotify-bridge.py/qs?"; fi
fi

if grep -q 'scenegraph is not functional' "$log"; then
    warn "the scene graph didn't start (no usable Vulkan for this display): QML loaded and was checked, nothing rendered"
fi

echo "── eager singletons"
if kill -0 "$pid" 2>/dev/null; then
    targets=$(qs ipc --pid "${qspid:-0}" show 2>&1)
    # shell.qml's eager list: a target missing here means the service was never built
    # (the `readonly property var _x: Services.X` trap — see CLAUDE.md, shell.qml).
    for t in cursor cursoreffects albumscheme osd overview; do
        if grep -qE "^target $t\$" <<<"$targets"; then ok "ipc target: $t"
        else fail "ipc target missing: $t"; fi
    done
fi

echo "── overview"
if kill -0 "$pid" 2>/dev/null; then
    shot 00-desktop
    # A fresh profile opens the first-run welcome over everything; it has been built and
    # scanned by now, so close it — the panel and page shots below would all show it.
    qs ipc --pid "${qspid:-0}" call welcome close >/dev/null 2>&1; sleep 0.5
    qs ipc --pid "${qspid:-0}" call overview open >/dev/null 2>&1 || fail "overview open failed"
    sleep 5   # nothing inside it exists until it's opened
    shot 01-overview
    qs ipc --pid "${qspid:-0}" call overview close >/dev/null 2>&1
    sleep 1
    n=$(grep -cE 'TypeError|Binding loop|QTextCursor' "$log")
    if [ "$n" -eq 0 ]; then ok "no TypeError / binding loop after opening it"
    else fail "$n TypeError/Binding loop line(s):"; grep -E 'TypeError|Binding loop|QTextCursor' "$log" | sort | uniq -c | sort -rn | head -8 | sed 's/^/        /'; fi
    kill -0 "$pid" 2>/dev/null || fail "the shell died while the overview was open"
fi

# Bar panels are Loader-built on open, inside Bar's window: "the shell loaded" says nothing
# about them. The largest files in the tree live here (ClockPanel, WallpaperPanel,
# ColorSchemePanel…). Open each over IPC (`panel toggle`, UiState), close it, then scan.
echo "── bar panels"
if kill -0 "$pid" 2>/dev/null; then
    before=$(wc -l <"$log")
    panels=(wallpaper colorScheme equalizer media wifi bluetooth gaming clock notifications
            brightness window layout stats clipboard timer claude screentime inactivity tasks clips update)
    for p in "${panels[@]}"; do
        qs ipc --pid "${qspid:-0}" call panel toggle "$p" >/dev/null 2>&1 || { fail "panel $p: ipc failed"; break; }
        sleep 1.2
        shot "panel-$p"
        qs ipc --pid "${qspid:-0}" call panel close >/dev/null 2>&1
        sleep 0.4
    done
    hits=$(tail -n +"$((before + 1))" "$log" | grep -iE "$hard|TypeError|Binding loop")
    if [ -n "$hits" ]; then
        fail "errors while opening the bar panels:"; echo "$hits" | sort | uniq -c | sort -rn | head -10 | sed 's/^/        /'
    else
        ok "opened ${#panels[@]} bar panels, no load failure or TypeError"
    fi
    kill -0 "$pid" 2>/dev/null || fail "the shell died while opening bar panels"
fi

# Settings pages are built only when shown, so a page that fails to load (a bad
# property, an unresolved type) is invisible to everything above — WallpaperPage once
# blanked itself over an `onClicked` on a PanelButton. Open every one, then scan.
echo "── settings pages"
if kill -0 "$pid" 2>/dev/null; then
    before=$(wc -l <"$log")
    pages=0
    for f in modules/settings/pages/*.qml; do
        qs ipc --pid "${qspid:-0}" call settings page "$(basename "$f")" >/dev/null 2>&1 || { fail "settings page $(basename "$f"): ipc failed"; break; }
        pages=$((pages + 1))
        sleep 1
        shot "page-$(basename "$f" .qml)"
    done
    qs ipc --pid "${qspid:-0}" call settings close >/dev/null 2>&1
    sleep 1
    hits=$(tail -n +"$((before + 1))" "$log" | grep -iE "$hard|TypeError|Binding loop")
    if [ -n "$hits" ]; then
        fail "errors while opening the settings pages:"; echo "$hits" | sort | uniq -c | sort -rn | head -10 | sed 's/^/        /'
    else
        ok "opened $pages settings pages, no load failure or TypeError"
    fi
    kill -0 "$pid" 2>/dev/null || fail "the shell died while opening settings pages"
fi

# The lock screen is built only while locked. Last, because there is no unlock over
# IPC (by design, services/Lock.qml) — the throwaway is killed locked, which is fine.
echo "── lock screen"
if kill -0 "$pid" 2>/dev/null; then
    before=$(wc -l <"$log")
    qs ipc --pid "${qspid:-0}" call lock lock >/dev/null 2>&1 || fail "lock: ipc failed"
    sleep 3
    shot lock
    st=$(qs ipc --pid "${qspid:-0}" call lock status 2>&1)
    case $st in locked*) ok "locked: ${st%%  ·*}" ;; *) warn "lock status: $st" ;; esac
    hits=$(tail -n +"$((before + 1))" "$log" | grep -iE "$hard|TypeError|Binding loop")
    if [ -n "$hits" ]; then
        fail "errors while locked:"; echo "$hits" | sort | uniq -c | sort -rn | head -10 | sed 's/^/        /'
    else
        ok "lock screen built, no load failure or TypeError"
    fi
fi

echo "── ${#fails[@]} failed, ${#warns[@]} warning(s) — log: $log"
echo "    (a green smoke means 'it starts', not 'it works'. Reload it yourself for that.)"
[ ${#fails[@]} -eq 0 ]
