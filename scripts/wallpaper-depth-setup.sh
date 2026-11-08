#!/usr/bin/env bash
# ── wallpaper-depth-setup.sh ──────────────────────────────────────────────────
# Build the private Python environment the depth clock needs, and fetch its two models:
#
#     wallpaper-depth-setup.sh [DIR]        DIR defaults to $XDG_DATA_HOME/quicktest/depth
#
# Run by the "Depth clock" tile in Settings › Wallpaper (the shell passes DIR); also fine by hand.
# Needs `uv` (pacman -S uv) and the network. Needs no root, and writes only under DIR:
#
#     DIR/venv     rembg, onnxruntime, numpy, pillow, huggingface-hub   (~1 GB)
#     DIR/models   Depth Anything V2 small (~100 MB), BiRefNet (~1 GB)
#     DIR/ready    written last: its presence is what the shell checks
#
# A separate environment, and Python 3.13 on purpose: onnxruntime's wheels trail new Python
# releases (the system Python here is newer), and `uv` fetches a matching interpreter itself.
# Nothing is installed system-wide, so removing the feature is `rm -r DIR`.
# Progress lines start with "::" — the shell shows the last one.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

dir="${1:-${XDG_DATA_HOME:-$HOME/.local/share}/quicktest/depth}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

command -v uv >/dev/null || { echo "wallpaper-depth-setup: uv isn't installed (pacman -S uv)" >&2; exit 3; }

mkdir -p "$dir"
rm -f "$dir/ready"

echo ":: Creating the Python environment"
uv venv --quiet --python 3.13 --allow-existing "$dir/venv"

echo ":: Installing packages"
uv pip install --quiet --python "$dir/venv/bin/python" \
    rembg pillow numpy huggingface-hub onnxruntime

echo ":: Downloading the models"
"$dir/venv/bin/python" "$here/wallpaper-depth.py" --prepare --models "$dir/models"

touch "$dir/ready"
echo ":: Ready"
