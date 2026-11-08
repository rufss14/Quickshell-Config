#!/usr/bin/env bash
# ── karaoke-model.sh ──────────────────────────────────────────────────────────
# Fetch the Vosk speech model Karaoke's WORD matching uses for a language, into the
# place the shell looks first:
#
#     karaoke-model.sh pt            Portuguese  → $XDG_DATA_HOME/quicktest/vosk-pt
#     karaoke-model.sh --list        what it can fetch
#     karaoke-model.sh --dry-run pt  say what it would do, and do nothing
#
# A model is for ONE language (the shell picks the one for the song's own language,
# detected from its lyrics, or the one pinned in Media › Settings › Karaoke). Without a
# model for a song's language Karaoke still runs, judging TIMING alone, and says so.
#
# The small models are 32–50 MB (alphacephei.com/vosk/models). This is run by hand,
# downloads from alphacephei.com over https (also run by the "Speech model" row in Media › Settings), needs no root, writes only under
# $XDG_DATA_HOME/quicktest, and refuses a download that does not unpack to a model.
# Names and versions are from Vosk's own model-list.json, 2026-10-17; `python3` does the
# unpacking (the standard library's zipfile), so there is no `unzip` dependency.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# code → the model's published name. The code is what the shell's language table uses
# (services/karaoke.js LANGS[].model).
declare -A MODELS=(
    [en-us]=vosk-model-small-en-us-0.15
    [pt]=vosk-model-small-pt-0.3
    [es]=vosk-model-small-es-0.42
    [fr]=vosk-model-small-fr-0.22
    [de]=vosk-model-small-de-0.15
    [it]=vosk-model-small-it-0.22
    [nl]=vosk-model-small-nl-0.22
    [ru]=vosk-model-small-ru-0.22
)
# What people type for the shell's language codes.
declare -A ALIAS=( [en]=en-us [english]=en-us [portuguese]=pt [spanish]=es [french]=fr [german]=de [italian]=it [dutch]=nl [russian]=ru )

dry=0
lang=""
for a in "$@"; do
    case "$a" in
        --list)
            printf '%s\n' "${!MODELS[@]}" | sort | while read -r c; do printf '  %-6s %s\n' "$c" "${MODELS[$c]}"; done
            exit 0 ;;
        --dry-run) dry=1 ;;
        -h|--help) sed -n 2,19p "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) echo "karaoke-model: unknown option $a" >&2; exit 2 ;;
        *) lang="$a" ;;
    esac
done
[ -n "$lang" ] || { echo "usage: karaoke-model.sh [--dry-run] <language>   (--list for the languages)" >&2; exit 2; }
lang="${lang,,}"
lang="${ALIAS[$lang]:-$lang}"
name="${MODELS[$lang]:-}"
[ -n "$name" ] || { echo "karaoke-model: no model for '$lang' — try --list" >&2; exit 2; }

data="${XDG_DATA_HOME:-$HOME/.local/share}/quicktest"
dest="$data/vosk-$lang"
url="https://alphacephei.com/vosk/models/$name.zip"

if [ -d "$dest" ] && [ -n "$(ls -A "$dest" 2>/dev/null)" ]; then
    echo "karaoke-model: $dest already has a model — remove it first to fetch again"
    exit 0
fi
echo "karaoke-model: $name"
echo "  from $url"
echo "  to   $dest"
[ "$dry" = 1 ] && exit 0

command -v curl >/dev/null || { echo "karaoke-model: needs curl" >&2; exit 1; }
command -v python3 >/dev/null || { echo "karaoke-model: needs python3" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
curl -fL --progress-bar --max-time 900 -o "$tmp/model.zip" "$url"

# Unpack into the temp dir, and only move it into place if it is a model: a model directory holds the
# acoustic model (am/final.mdl, or final.mdl at its top) — a truncated download or an error page is not.
python3 -I - "$tmp/model.zip" "$tmp/out" "$name" <<'PY'
import os, sys, zipfile
src, out, name = sys.argv[1:4]
z = zipfile.ZipFile(src)
for n in z.namelist():                                   # no path may leave the directory we unpack into
    p = os.path.normpath(os.path.join(out, n))
    if not (p == out or p.startswith(out + os.sep)):
        sys.exit("refusing an archive with a path outside its own directory: " + n)
z.extractall(out)
root = os.path.join(out, name)
if not os.path.isdir(root):
    sys.exit("the download did not contain " + name)
ok = any(os.path.exists(os.path.join(root, *p)) for p in (("am", "final.mdl"), ("final.mdl",)))
if not ok:
    sys.exit("the download is not a Vosk model (no final.mdl)")
PY
mkdir -p "$data"
mv "$tmp/out/$name" "$dest"
echo "karaoke-model: done — $(du -sh "$dest" | cut -f1) in $dest"
echo "  Karaoke will use it for $lang songs the next time you switch it on."
