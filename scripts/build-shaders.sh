#!/usr/bin/env bash
# ── build-shaders.sh ──────────────────────────────────────────────────────────
# Compiles the shell's own shaders — shaders/*.src.frag — to the .qsb files QML loads.
#
#     bash scripts/build-shaders.sh
#
# Each *.src.frag has `//@FRONT` where shaders/wavefront.glsl is pasted in: the one
# shape every wave shader draws (the wallpaper's water and the shell's infection),
# kept in one file so the picture and the chrome can never move apart. The pasted
# source is a temp file; only the .qsb lands in shaders/, and is committed — nothing
# at runtime rebuilds it (see .gitignore), so run this after editing any of them.
#
# Needs qsb, from qt6-shadertools — a build-time tool only. A machine that merely
# RUNS the shell never needs it: the compiled .qsb ships in the repo.
#
# `--qt6` is qsb's standard Qt 6 target set (SPIR-V plus the GLSL/HLSL/MSL variants),
# the same one the shell's other shader (liquidglass) was built with.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

DIR="$(cd "$(dirname "$(readlink -f "$0")")/../shaders" && pwd)"
QSB="${QSB:-/usr/lib/qt6/bin/qsb}"
if [[ ! -x "$QSB" ]]; then
    QSB="$(command -v qsb || true)"
fi
[[ -n "$QSB" && -x "$QSB" ]] || { echo "qsb not found — install qt6-shadertools" >&2; exit 1; }

FRONT="$DIR/wavefront.glsl"
[[ -r "$FRONT" ]] || { echo "missing $FRONT" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

shopt -s nullglob
built=0
for src in "$DIR"/*.src.frag; do
    name="$(basename "$src" .src.frag)"
    # A shader with no `//@FRONT` line (depthmask) is not a wave shader and is compiled as it stands.
    if grep -q '^//@FRONT$' "$src"; then
        # Pasted by line, so the front's own text is never re-parsed as a pattern.
        while IFS= read -r line || [[ -n "$line" ]]; do
            if [[ "$line" == "//@FRONT" ]]; then cat "$FRONT"; else printf '%s\n' "$line"; fi
        done < "$src" > "$TMP/$name.frag"
    else
        cp "$src" "$TMP/$name.frag"
    fi
    "$QSB" --qt6 -o "$DIR/$name.frag.qsb" "$TMP/$name.frag"
    echo "built shaders/$name.frag.qsb"
    built=$((built + 1))
done
[[ "$built" -gt 0 ]] || { echo "no *.src.frag in $DIR" >&2; exit 1; }
