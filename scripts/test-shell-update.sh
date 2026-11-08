#!/usr/bin/env bash
# ── test-shell-update.sh ──────────────────────────────────────────────────────
# Runs the REAL scripts/shell-update.sh against a fake install and file:// releases
# built here, signed with throwaway keys. Checks that a good release installs
# (user files and presets untouched, dropped files removed) and that every bad one
# — wrong key, tampered archive, mislabelled version, git checkout — changes nothing.
#
#     bash scripts/test-shell-update.sh
#
# Safe to run: everything lives in a mktemp dir; no network, no real shell touched
# (the fake install's reload-quickshell.sh is a stub).
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); printf '  FAIL  %s\n          got  %s\n          want %s\n' "$1" "$2" "$3"; fi; }

ssh-keygen -q -t ed25519 -N "" -f "$T/key"   -C t >/dev/null
ssh-keygen -q -t ed25519 -N "" -f "$T/other" -C t >/dev/null

# A fake installed 0.3: its own key, last release's file list, user state.
fresh() {
    rm -rf "$T/inst" "$T/cache"; mkdir -p "$T/inst"/{config,scripts,release,presets,old}
    cp "$HERE/shell-update.sh" "$T/inst/scripts/"
    printf '#!/bin/sh\ntouch "%s/reloaded"\n' "$T" > "$T/inst/scripts/reload-quickshell.sh"
    printf 'quicktest-release namespaces="quicktest-release" %s\n' "$(cut -d' ' -f1,2 "$T/key.pub")" \
        > "$T/inst/release/allowed_signers"
    echo 'readonly property string version: "0.3"' > "$T/inst/config/Config.qml"
    echo old  > "$T/inst/shell.qml"
    echo gone > "$T/inst/old/dropped.qml"
    echo mine > "$T/inst/presets/bar.json"
    echo key  > "$T/inst/ai-keys.json"
    printf '%s\n' shell.qml old/dropped.qml config/Config.qml presets/bar.json > "$T/inst/.release-files"
    rm -f "$T/reloaded"
}

# release <dir> <tag> <archive-version> <signing key>
release() {
    local R="$T/rel/$1" N="$T/build/quicktest"
    rm -rf "$R" "$T/build"; mkdir -p "$R" "$N"/{config,scripts,release,presets,colorschemes}
    cp "$T/inst/release/allowed_signers" "$N/release/"
    echo "readonly property string version: \"$3\"" > "$N/config/Config.qml"
    echo new  > "$N/shell.qml"
    echo ship > "$N/presets/bar.json"
    echo ship > "$N/presets/widgets.json"
    echo ship > "$N/colorschemes/Ship.json"
    printf '%s\n' shell.qml config/Config.qml presets/bar.json presets/widgets.json \
        colorschemes/Ship.json release/allowed_signers .release-files > "$N/.release-files"
    mkdir -p "$R/$2"
    tar -cJf "$R/$2/quicktest.tar.xz" -C "$T/build" quicktest
    (cd "$R/$2" && sha256sum quicktest.tar.xz > SHA256SUMS)
    ssh-keygen -q -Y sign -f "$4" -n quicktest-release "$R/$2/SHA256SUMS" 2>/dev/null
}

run() {   # run <reldir> <tag>
    QUICKTEST_RELEASE_URL="file://$T/rel/$1" XDG_CACHE_HOME="$T/cache" \
        bash "$T/inst/scripts/shell-update.sh" install o/r "$2" >/dev/null 2>&1
    cat "$T/cache/quicktest-shell-update/status" 2>/dev/null
}
untouched() { [ "$(cat "$T/inst/shell.qml")" = old ] && [ -f "$T/inst/old/dropped.qml" ] && echo yes || echo no; }

# ── good release ──
fresh; release good v0.4 0.4 "$T/key"
check "good: status"            "$(run good v0.4)"                     "done 0.4"
check "good: shipped replaced"  "$(cat "$T/inst/shell.qml")"           "new"
check "good: dropped removed"   "$([ -e "$T/inst/old" ] && echo yes || echo no)" "no"
check "good: preset kept"       "$(cat "$T/inst/presets/bar.json")"    "mine"
check "good: new preset added"  "$(cat "$T/inst/presets/widgets.json")" "ship"
check "good: scheme added"      "$(cat "$T/inst/colorschemes/Ship.json")" "ship"
check "good: secret kept"       "$(cat "$T/inst/ai-keys.json")"        "key"
check "good: list replaced"     "$(grep -c . "$T/inst/.release-files")" "7"
check "good: restarted"         "$([ -f "$T/reloaded" ] && echo yes || echo no)" "yes"

# ── refused, nothing changed ──
fresh; release evil v0.4 0.4 "$T/other"
check "wrong key"          "$(run evil v0.4)"   "fail Signature check failed — not installing."
check "wrong key: intact"  "$(untouched)"       "yes"

fresh; release tamper v0.4 0.4 "$T/key"; echo x >> "$T/rel/tamper/v0.4/quicktest.tar.xz"
check "tampered"           "$(run tamper v0.4)" "fail Download is corrupt (hash mismatch)."
check "tampered: intact"   "$(untouched)"       "yes"

fresh; release lie v0.5 0.4 "$T/key"
check "version mismatch"   "$(run lie v0.5)"    "fail Archive version doesn't match v0.5."
check "mismatch: intact"   "$(untouched)"       "yes"

fresh; mkdir "$T/inst/.git"; release good v0.4 0.4 "$T/key"
check "git checkout"       "$(run good v0.4)"   "fail This copy is a git checkout — update it with git."

fresh
check "bad tag"            "$(run good 'v0.4;rm')" "fail Bad release tag."
check "no restart on fail" "$([ -f "$T/reloaded" ] && echo yes || echo no)" "no"

echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
