#!/usr/bin/env bash
# ── shell-update.sh ───────────────────────────────────────────────────────────
# Installs a newer release of THIS shell over itself. Launched detached by
# services/ShellUpdate.qml; the release side is the maintainer's qtrelease.
#
#   shell-update.sh install <owner/repo> <tag>
#
# ── Trust ─────────────────────────────────────────────────────────────────────
# A release is three assets: quicktest.tar.xz, SHA256SUMS (its hash) and
# SHA256SUMS.sig, an SSH signature over SHA256SUMS. The signature is checked
# against release/allowed_signers from the copy ALREADY INSTALLED here — never one
# that arrived with the download — so an update is accepted only if the holder of
# the release key signed it. Owning the GitHub repo is not enough. Nothing in the
# shell directory is touched until signature, hash, layout and version all check out.
#
# ── What it writes ────────────────────────────────────────────────────────────
# Shipped files are replaced. Files the previous release shipped and this one
# doesn't are removed (from .release-files, the list each release carries).
# Everything else — secrets, theming/, plugin/build/, anything the user added —
# is not in either list and is never touched. presets/ and colorschemes/ are the
# user's own saved library (Config's JsonStores write there), so a release only
# ADDS files to them: an existing preset is never overwritten or deleted.
#
# ── Why it ends in a restart ──────────────────────────────────────────────────
# Quickshell hot-reloads on EVERY watched file change, no debounce
# (EngineGeneration::onFileChanged), so ~500 files landing in place would be a
# reload storm over a half-new tree. The service turns `Quickshell.watchFiles` off
# before launching this, and this restarts the shell once at the end. It runs
# setsid-detached so that restart (or any reload) cannot kill it mid-copy.
#
# ── Status protocol ───────────────────────────────────────────────────────────
# One line at a time in $WORK/status (overwritten, not appended):
#   step <text>     working
#   fail <text>     stopped; before "Installing" nothing here was changed
#   done <version>  installed; read back by the restarted shell to say so
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

# Everything is inside main, called on the LAST line with `exit` beside it: bash
# reads a script incrementally, and this file is one of the files being replaced.
main() {
    local SHELL_DIR WORK STAGE REPO TAG VER
    SHELL_DIR="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
    WORK="${XDG_CACHE_HOME:-$HOME/.cache}/quicktest-shell-update"
    STAGE="$WORK/stage"
    mkdir -p "$WORK"

    status() { printf '%s\n' "$*" > "$WORK/status.tmp" && mv -f "$WORK/status.tmp" "$WORK/status"; }
    die()    { status "fail $*"; exit 1; }

    [ "${1:-}" = install ] || { echo "usage: shell-update.sh install <owner/repo> <tag>" >&2; exit 64; }
    REPO="${2:-}"; TAG="${3:-}"

    # Trust boundary: both arrive from a GitHub API response via QML.
    [[ "$REPO" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || die "Bad repository name."
    [[ "$TAG" =~ ^v[0-9]+(\.[0-9]+){0,3}$ ]]           || die "Bad release tag."
    VER="${TAG#v}"

    exec 9>"$WORK/lock"
    flock -n 9 || die "An update is already installing."

    [ -e "$SHELL_DIR/.git" ] && die "This copy is a git checkout — update it with git."
    local KEYS="$SHELL_DIR/release/allowed_signers"
    [ -s "$KEYS" ] || die "No release key in this install (release/allowed_signers)."
    local t; for t in curl ssh-keygen sha256sum tar xz; do
        command -v "$t" >/dev/null || die "Missing $t."
    done

    rm -rf "$STAGE"; mkdir -p "$STAGE/x"
    status "step Downloading $TAG…"
    # The override exists for scripts/test-shell-update.sh (a file:// release); the
    # signature check below doesn't care where the bytes came from.
    local URL="${QUICKTEST_RELEASE_URL:-https://github.com/$REPO/releases/download}/$TAG" a
    for a in quicktest.tar.xz SHA256SUMS SHA256SUMS.sig; do
        curl -fsSL --max-time 300 -o "$STAGE/$a" "$URL/$a" || die "Download failed ($a)."
    done

    status "step Verifying signature…"
    ssh-keygen -Y verify -f "$KEYS" -I quicktest-release -n quicktest-release \
        -s "$STAGE/SHA256SUMS.sig" < "$STAGE/SHA256SUMS" >/dev/null 2>&1 \
        || die "Signature check failed — not installing."
    [ "$(awk '{print $2}' "$STAGE/SHA256SUMS")" = "quicktest.tar.xz" ] || die "Unexpected SHA256SUMS."
    (cd "$STAGE" && sha256sum -c --strict --quiet SHA256SUMS >/dev/null 2>&1) \
        || die "Download is corrupt (hash mismatch)."

    status "step Unpacking…"
    # -c, not -q: an early-exiting grep SIGPIPEs tar, and pipefail then hides the hit.
    [ "$(tar -tJf "$STAGE/quicktest.tar.xz" | grep -cvE '^quicktest/')" = 0 ] \
        || die "Unexpected archive layout."
    tar -xJf "$STAGE/quicktest.tar.xz" --no-same-owner -C "$STAGE/x" || die "Could not unpack."
    local NEW="$STAGE/x/quicktest"
    [ -f "$NEW/shell.qml" ] && [ -f "$NEW/.release-files" ] || die "Archive is missing files."
    grep -qF "readonly property string version: \"$VER\"" "$NEW/config/Config.qml" \
        || die "Archive version doesn't match $TAG."

    status "step Installing $VER…"
    # Removed upstream: in the old list, not in the new. The list is from the
    # installed copy; every path is relative and dot-dot-free or it's skipped.
    if [ -f "$SHELL_DIR/.release-files" ]; then
        local f
        comm -23 <(sort -u "$SHELL_DIR/.release-files") <(sort -u "$NEW/.release-files") |
        while IFS= read -r f; do
            case "$f" in ""|/*|*..*|presets/*|colorschemes/*) continue ;; esac
            rm -f -- "$SHELL_DIR/$f"
            rmdir -p --ignore-fail-on-non-empty -- "$(dirname "$SHELL_DIR/$f")" 2>/dev/null || true
        done
    fi
    # --remove-destination: a NEW inode per file, so anything still reading the old
    # one (this script, a running helper) keeps the old bytes intact.
    local e base
    for e in "$NEW"/* "$NEW"/.[!.]*; do
        [ -e "$e" ] || continue
        base="$(basename "$e")"
        case "$base" in
            presets|colorschemes)
                mkdir -p "$SHELL_DIR/$base"
                cp -a --update=none "$e/." "$SHELL_DIR/$base/" || die "Install failed ($base)." ;;
            *)  cp -a --remove-destination "$e" "$SHELL_DIR/" || die "Install failed ($base)." ;;
        esac
    done
    rm -rf "$STAGE"

    status "done $VER"
    # Close the lock fd first: the restarted shell inherits every open fd from here,
    # and a quickshell holding fd 9 would hold this lock for its whole life.
    exec 9>&-
    bash "$SHELL_DIR/scripts/reload-quickshell.sh" >/dev/null 2>&1 || true
}

main "$@"; exit $?
