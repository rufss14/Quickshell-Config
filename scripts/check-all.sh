#!/usr/bin/env bash
# ── check-all.sh ──────────────────────────────────────────────────────────────
# Every static checker, the QML syntax sweep, and every scripts/test-* file, in
# one go. Exits non-zero if anything failed.
#
#     bash scripts/check-all.sh             checkers + syntax sweep + tests
#     bash scripts/check-all.sh --static    checkers + syntax sweep only (no test scripts run)
#
# A pass means "no typos and the logic tests agree", NOT "the shell works": it
# never launches Quickshell. A reload is still the actual test (see CLAUDE.md,
# "Checking your work", steps 3-4).
#
# Why this reads output and not just exit codes: check-qml-aliases.py and
# check-qml-duplicates.py ALWAYS exit 0 and only print `name=N`. Trusting the exit
# status would report them green while they listed a hard load failure. So a
# `name=N` line with N > 0 is a failure too, whatever the exit code said.
#
# check-qml-fillheight.py is gated against a per-file baseline of known, untriaged findings.
# ─────────────────────────────────────────────────────────────────────────────
set -u
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2

static_only=0
[ "${1:-}" = "--static" ] && static_only=1

out=$(mktemp); trap 'rm -f "$out"' EXIT
fails=(); skips=(); passed=0

# run NAME CMD… — pass on exit 0 AND no `word=N` (N>0) summary line.
run() {
    local name=$1; shift
    if timeout 120 "$@" >"$out" 2>&1 && ! grep -qE '^[a-z-]+=[1-9][0-9]*$' "$out"; then
        passed=$((passed + 1)); printf '  ok    %s\n' "$name"
    else
        fails+=("$name"); printf '  FAIL  %s\n' "$name"; sed 's/^/        /' "$out" | tail -15
    fi
}
skip() { skips+=("$1: $2"); printf '  skip  %s (%s)\n' "$1" "$2"; }

echo "── static checkers"
for c in aliases duplicates readonly-anim final palette imports singletons qmldir; do
    run "check-qml-$c" python3 scripts/check-qml-$c.py
done
run check-config-persisted python3 scripts/check-config-persisted.py
run check-contrast python3 scripts/check-contrast.py
if python3 -c 'import fontTools' 2>/dev/null; then
    run check-glyphs python3 scripts/check-glyphs.py
else
    skip check-glyphs "needs fontTools"
fi

# Informational only — see the header.
# Gated against a per-file baseline (scripts/fillheight-baseline.txt): the known findings each
# want a look at the panel, so only a file that GAINS one fails.
mapfile -t qml < <(find . -name '*.qml' -not -path './config/settings/*' -not -path './plugin/build/*')
fh_over=$(python3 scripts/check-qml-fillheight.py "${qml[@]}" 2>&1 | cut -d: -f1 | sed 's|^\./||' | sort | uniq -c \
    | awk 'NR == FNR { if ($0 !~ /^#/ && NF == 2) base[$1] = $2; next } $1 > ($2 in base ? base[$2] : 0) { print "        " $2 ": " $1 " (baseline " ($2 in base ? base[$2] : 0) ")" }' \
        scripts/fillheight-baseline.txt -)
if [ -z "$fh_over" ]; then
    passed=$((passed + 1)); printf '  ok    check-qml-fillheight (against its baseline)\n'
else
    fails+=("check-qml-fillheight"); printf '  FAIL  check-qml-fillheight: new layout(s) inside a ColumnLayout with no Layout.fillHeight\n%s\n' "$fh_over"
fi
# Informational: comments that narrate history (docs/standards.md, "Comments"). Should only go down.
printf '  note  check-comment-history: %s comment(s) narrating history\n' "$(python3 scripts/check-comment-history.py --count)"
# Gated: there are zero findings, so any new one is a regression.
hp=$(python3 scripts/check-qml-hotpaths.py --count 2>/dev/null)
if [ "$hp" = "0" ]; then
    passed=$((passed + 1)); printf '  ok    check-qml-hotpaths\n'
else
    fails+=("check-qml-hotpaths"); printf '  FAIL  check-qml-hotpaths: %s per-frame source(s) with nothing to stop them\n' "$hp"
    python3 scripts/check-qml-hotpaths.py | sed -n '2,/^$/p' | sed 's/^/        /'
fi

echo "── syntax sweep (${#qml[@]} files)"
qmlformat=/usr/lib/qt6/bin/qmlformat
[ -x "$qmlformat" ] || qmlformat=$(command -v qmlformat || true)
if [ -z "$qmlformat" ]; then
    skip "qml syntax" "no qmlformat"
else
    # The two sed expressions, in this order — see CLAUDE.md "The syntax idiom".
    # 0 bytes out of qmlformat = it did not parse.
    tmp=$(mktemp --suffix=.qml); bad=()
    for f in "${qml[@]}"; do
        sed -E 's/\?\.(\[|\()/\1/g; s/\?\./\./g' "$f" >"$tmp"
        [ "$("$qmlformat" "$tmp" 2>/dev/null | wc -c)" -gt 0 ] || bad+=("$f")
    done
    rm -f "$tmp"
    if [ ${#bad[@]} -eq 0 ]; then
        passed=$((passed + 1)); echo "  ok    all parse"
    else
        fails+=("qml syntax"); printf '  FAIL  did not parse: %s\n' "${bad[@]}"
    fi
fi

if [ $static_only -eq 0 ]; then
    echo "── tests"
    for t in scripts/test-*; do
        # A test that says so in its header drives the LIVE desktop (test-discord-press.py
        # presses Ctrl+Shift+M in your real Discord). Never part of a sweep: run it by hand.
        if head -n 12 "$t" | grep -q 'against LIVE'; then skip "$t" "runs against live services"; continue; fi
        case $t in
            *.js)
                if command -v bun >/dev/null; then run "$t" bun "$t"
                elif command -v node >/dev/null; then run "$t" node "$t"
                else skip "$t" "needs bun or node"; fi ;;
            *.py) run "$t" python3 "$t" ;;
            *.sh) run "$t" bash "$t" ;;
        esac
    done
fi

echo "── $passed passed, ${#fails[@]} failed, ${#skips[@]} skipped"
[ ${#fails[@]} -eq 0 ] || { printf 'failed: %s\n' "${fails[@]}"; exit 1; }
