#!/usr/bin/env python3
"""theme-logo.py — a brand's mark, lifted out of an app icon in the INSTALLED theme.

    theme-logo.py OUT NAME [NAME…]

The stats pill's devices ring shows a Razer device as Razer's snake, the user's
call. A brand's logo is never shipped in this repo (it's published; see CLAUDE.md,
the Wallpaper Engine precedent), so it's taken from whatever icon theme is on this
machine: the first NAME found (e.g. Papirus's `razercommander`) is read, its tile
and its shadow/highlight layers dropped, and the mark alone written to OUT (under
the cache), cropped to itself. The shell draws it as a stencil (TintedIcon) in the
palette's colour, so the file's own colours never show.

"Tile and effects" is a structural guess that fits Papirus-style app icons:
every <rect> is the tile or its shadow, and any shape with opacity < 1 is a shadow
or a highlight. What's left is the mark. Prints OUT on success and nothing on
failure (no theme icon, nothing left after stripping) — the caller then keeps
the plain glyph. Crops with ImageMagick when it's there; without it the tile's box
is the frame, which only adds some margin.
"""
import os
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

SVG_NS = "http://www.w3.org/2000/svg"
ET.register_namespace("", SVG_NS)


def icon_dirs():
    home = os.path.expanduser("~")
    data_home = os.environ.get("XDG_DATA_HOME") or os.path.join(home, ".local/share")
    dirs = [os.path.join(home, ".icons"), os.path.join(data_home, "icons")]
    for d in (os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share").split(":"):
        if d:
            dirs.append(os.path.join(d, "icons"))
    return [d for d in dirs if os.path.isdir(d)]


def size_rank(path):
    """Scalable first, then the biggest fixed size: the most detail to keep."""
    if "/scalable/" in path:
        return 100000
    m = re.search(r"/(\d+)x\d+(@\d+x)?/", path)
    return int(m.group(1)) if m else 0


def find_icon(names):
    for name in names:
        found = []
        for base in icon_dirs():
            for root, _dirs, files in os.walk(base):
                if name + ".svg" in files:
                    found.append(os.path.join(root, name + ".svg"))
        if found:
            return max(found, key=size_rank)
    return None


def opacity(el):
    style = el.get("style", "")
    m = re.search(r"(?:^|;)\s*opacity\s*:\s*([\d.]+)", style)
    v = m.group(1) if m else el.get("opacity")
    try:
        return float(v) if v is not None else 1.0
    except ValueError:
        return 1.0


def strip(tree):
    """Drop the tile and the effect layers; returns the tile's box, or None."""
    root = tree.getroot()
    tile = None
    for parent in list(root.iter()):
        for el in list(parent):
            tag = el.tag.split("}")[-1]
            if tag == "rect" or opacity(el) < 1:
                if tag == "rect" and opacity(el) >= 1 and tile is None:
                    try:
                        tile = [float(el.get(k, 0)) for k in ("x", "y", "width", "height")]
                    except ValueError:
                        pass
                parent.remove(el)
    return tile


def has_shapes(root):
    return any(el.tag.split("}")[-1] in ("path", "circle", "ellipse", "polygon") for el in root.iter())


def crop(path, fallback):
    """The mark's own box, square, from a trimmed render; else the tile's."""
    scale = 4
    try:
        out = subprocess.run(
            ["magick", "-background", "none", "-density", str(96 * scale), path,
             "-trim", "-format", "%w %h %X %Y", "info:"],
            capture_output=True, text=True, timeout=10)
        w, h, x, y = (float(v) for v in out.stdout.split())
        box = [x / scale, y / scale, w / scale, h / scale]
    except (OSError, ValueError, subprocess.TimeoutExpired):
        box = fallback
    if not box or box[2] <= 0 or box[3] <= 0:
        return None
    side = max(box[2], box[3])
    return [box[0] - (side - box[2]) / 2, box[1] - (side - box[3]) / 2, side, side]


def main():
    if len(sys.argv) < 3:
        return
    out = os.path.abspath(sys.argv[1])
    src = find_icon(sys.argv[2:])
    if not src:
        return
    try:
        tree = ET.parse(src)
    except (ET.ParseError, OSError):
        return
    root = tree.getroot()
    tile = strip(tree)
    if not has_shapes(root):
        return
    # Keep the source's coordinate space while rendering, so the crop's pixels
    # map back onto it.
    w = re.sub(r"[^\d.]", "", root.get("width", "")) or "64"
    h = re.sub(r"[^\d.]", "", root.get("height", "")) or "64"
    root.set("viewBox", root.get("viewBox") or f"0 0 {w} {h}")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    tree.write(out)
    box = crop(out, tile)
    if box:
        root.set("viewBox", " ".join(f"{v:.3f}" for v in box))
        root.set("width", f"{box[2]:.3f}")
        root.set("height", f"{box[3]:.3f}")
        tree.write(out)
    print(out)


if __name__ == "__main__":
    main()
