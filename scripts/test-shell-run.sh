#!/usr/bin/env bash
# scripts/shell-run.sh against a fake `qs` that exits with scripted codes.
#     bash scripts/test-shell-run.sh
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL $1: got '$2', want '$3'"; fi; }

# The fake: pops the next exit code off $T/codes and records QS_SAFE for each start.
mkdir -p "$T/bin"
cat >"$T/bin/qs" <<'EOF'
#!/usr/bin/env bash
code=$(head -n1 "$FAKE/codes"); sed -i 1d "$FAKE/codes"
echo "${QS_SAFE:-unset}" >>"$FAKE/starts"
exit "${code:-0}"
EOF
printf '#!/bin/sh\necho "$@" >>"$FAKE/notes"\n' >"$T/bin/notify-send"
chmod +x "$T/bin/qs" "$T/bin/notify-send"

run() {   # run CODES... → starts (QS_SAFE per start, space-separated) and the exit code
    : >"$T/starts"; : >"$T/notes"; printf '%s\n' "$@" >"$T/codes"
    HOME="$T/home" XDG_CACHE_HOME="$T/cache" XDG_DATA_HOME="$T/data" XDG_STATE_HOME="$T/state" \
    FAKE="$T" PATH="$T/bin:$PATH" QS_BIN="$T/bin/qs" QS_CRASH_WINDOW=60 \
        bash "$HERE/shell-run.sh" 2>/dev/null
    echo "$? $(tr '\n' ' ' <"$T/starts" | sed 's/ $//')"
}

check "clean exit stops"         "$(run 0)"                     "0 0"
check "reload (TERM) stops"      "$(run 143)"                   "143 0"
check "SIGKILL stops"            "$(run 137)"                   "137 0"
check "bad argument stops"       "$(run 1)"                     "1 0"
check "one startup crash"        "$(run 255 143)"               "143 0 0"
check "segfault restarts"        "$(run 139 0)"                 "0 0 0"
check "two crashes → safe mode"  "$(run 255 255 143)"           "143 0 0 1"
check "safe mode crashes → stop" "$(run 255 255 255 255)"       "1 0 0 1 1"
QS_SAFE=1 check "QS_SAFE=1 starts safe" "$(QS_SAFE=1 run 0)"    "0 1"

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
