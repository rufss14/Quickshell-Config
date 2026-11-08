#!/usr/bin/env python3
"""
wpe-scan.py — list a Wallpaper Engine workshop folder for services/WallpaperEngine.qml.

    python3 scripts/wpe-scan.py <workshop-dir> [<texture-root>]

Output, tab separated, one item per line, the title LAST (the only field that can
hold anything):

    SKIPPED <n>
    ITEM <id> <type> <preview> <base> <props-json> <texdir> <title>

Two kinds of project.json are real wallpapers:

  * a normal one — it has a `file` (scene.json, a video, a web page);
  * a PRESET — no `file`, but a `dependency` on another workshop item and a
    `preset` blob of that item's property values (Steam's "Category: Preset").
    linux-wallpaperengine has no notion of presets, so the shell plays one as
    `--bg <base>` plus a `--set-property` per value. `base` is that item's id and
    `props` the values, already in the renderer's wire format (the same one
    WallpaperEngine's override cache holds):

        slider → "0.75"      bool → "1" / "0"      color → "#rrggbb" (the shell
        converts it to floats at launch; the renderer misreads a hex string)
        combo  → the option's value                textinput → the text

    A `scenetexture` value (the pictures a preset swaps in) is NOT a --set-property:
    the renderer stores it and never reads it. The scene binds the picture with a
    material `"usertextures": ["customimageleft"]`, and the renderer resolves that
    entry as a texture NAMED "customimageleft" — `materials/customimageleft.tex` in a
    mounted folder. So a preset with pictures gets a project folder of its own,
    <texture-root>/<id>/: the base's project.json and .pkg (see build_project) plus
    each picture as `materials/<key>.tex` (see write_tex). <texdir> is that folder
    and the shell hands it to the renderer as `--bg` instead of the base. (Not the
    renderer's working directory — the Arch package's wrapper `cd`s to /opt first.)

    Only keys the base scene actually declares survive. `preset` also carries
    Wallpaper Engine's own per-wallpaper settings (alignment, wec_* colour
    adjustment, rate, audioprocessing) which are not scene properties, and nothing
    outside the base's schema may reach the renderer's argv.

Anything else — unreadable, no file, a preset whose base isn't installed — is
counted in SKIPPED, never silently dropped.
"""
import json
import os
import sys

TEXT_TYPES = ("textinput",)

# TEXB0003's FreeImage ids (Data/Assets/Texture.h): the renderer decodes the embedded
# file with stb_image whenever this isn't FIF_UNKNOWN, and takes its size from it.
FIF = {"JPEG": 2, "PNG": 13}


def _load(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            j = json.load(f)
    except Exception:
        return None
    return j if isinstance(j, dict) else None


def _hex(value):
    try:
        r, g, b = (float(x) for x in str(value).replace(",", " ").split()[:3])
    except Exception:
        return None
    clamp = lambda x: max(0, min(255, round(x * 255)))
    return "#%02x%02x%02x" % (clamp(r), clamp(g), clamp(b))


def wire_value(spec, value, preset_dir):
    """One preset value in the renderer's wire format, or None to leave it out."""
    if value is None:
        return None
    kind = spec.get("type")
    if kind == "bool":
        return "1" if value in (True, 1, "1", "true") else "0"
    if kind == "slider":
        try:
            return str(float(value))
        except Exception:
            return None
    if kind == "color":
        return _hex(value)
    if kind == "combo":
        return str(value)
    if kind in TEXT_TYPES:
        return str(value)
    if kind == "scenetexture":
        # Relative to the preset's folder. Must stay inside it: the value is
        # hand-editable JSON and ends up as a path the renderer opens.
        root = os.path.realpath(preset_dir)
        full = os.path.realpath(os.path.join(root, str(value)))
        if full.startswith(root + os.sep) and os.path.isfile(full):
            return full
    return None


def write_tex(src, dest):
    """A Wallpaper Engine .tex (TEXV0005 / TEXB0003) holding the image file `src`
    as it is — JPEG and PNG verbatim, anything else re-encoded to PNG. True when
    written. Layout and field order are TextureParser.cpp's. Needs Pillow."""
    import io
    import struct
    try:
        from PIL import Image
        with Image.open(src) as im:
            w, h = im.size
            kind = im.format if im.format in FIF else None
            if kind:
                with open(src, "rb") as f:
                    data = f.read()
            else:
                buf = io.BytesIO()
                im.convert("RGBA").save(buf, "PNG")
                kind, data = "PNG", buf.getvalue()
    except Exception:
        return False
    tex = b"".join((
        b"TEXV0005\0", b"TEXI0001\0",
        # format ARGB8888 (unused for an embedded file), flags ClampUVs,
        # texture w/h, real w/h, one ignored word
        struct.pack("<7I", 0, 2, w, h, w, h, 0),
        b"TEXB0003\0", struct.pack("<II", 1, FIF[kind]),
        # one image, one mipmap: w, h, compression 0, uncompressed size, size
        struct.pack("<II", 1, w) + struct.pack("<IIii", h, 0, len(data), len(data)),
        data,
    ))
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    tmp = dest + ".tmp"
    with open(tmp, "wb") as f:
        f.write(tex)
    os.replace(tmp, dest)
    return True


def build_project(base, out):
    """Make `out` a project folder the renderer can play in place of `base`:
    `project.json` as a REAL copy, the scene's .pkg symlinked, and a `materials/`
    folder for the generated textures. False when `base` isn't a packed scene.

    Real copy, because the renderer's directory adapter canonical()s every path and
    refuses one that leaves the mounted folder — a symlinked project.json is "not
    found". The .pkg is the exception: its adapter opens the file itself. A scene
    unpacked into loose files would need every one of them copied, so it's left alone.
    Idempotent and never deletes: the renderer may be running from `out`."""
    pkgs = [n for n in ("scene.pkg", "gifscene.pkg") if os.path.isfile(os.path.join(base, n))]
    if not pkgs or not os.path.isfile(os.path.join(base, "project.json")):
        return False
    os.makedirs(os.path.join(out, "materials"), exist_ok=True)
    for name in pkgs:
        target, dest = os.path.join(base, name), os.path.join(out, name)
        if not (os.path.islink(dest) and os.readlink(dest) == target):
            tmp = dest + ".new"
            if os.path.lexists(tmp):
                os.remove(tmp)
            os.symlink(target, tmp)
            os.replace(tmp, dest)
    with open(os.path.join(base, "project.json"), "rb") as f:
        data = f.read()
    dest = os.path.join(out, "project.json")
    tmp = dest + ".new"
    with open(tmp, "wb") as f:
        f.write(data)
    os.replace(tmp, dest)
    return True


def preset_props(preset, schema, preset_dir):
    """(props, textures): wire values for --set-property, and {key: image path}
    for the scenetexture ones, which go through write_tex instead."""
    out, pics = {}, {}
    for key, value in preset.items():
        spec = schema.get(key)
        if not isinstance(spec, dict):
            continue
        w = wire_value(spec, value, preset_dir)
        if w is None:
            continue
        if spec.get("type") == "scenetexture":
            pics[key] = w
        else:
            out[key] = w
    return out, pics


def scan(workshop, texroot=None):
    rows, skipped = [], 0
    for d in sorted(os.listdir(workshop)):
        folder = os.path.join(workshop, d)
        j = _load(os.path.join(folder, "project.json"))
        if j is None:
            if os.path.exists(os.path.join(folder, "project.json")):
                skipped += 1
            continue
        source, base, props, texdir = j, "", {}, ""
        if not j.get("file"):
            dep = str(j.get("dependency") or "")
            b = _load(os.path.join(workshop, dep, "project.json")) if dep.isdigit() else None
            if not (b and b.get("file") and isinstance(j.get("preset"), dict)):
                skipped += 1
                continue
            schema = (b.get("general") or {}).get("properties") or {}
            source, base = b, dep
            props, pics = preset_props(j["preset"], schema, folder)
            if texroot and pics:
                out = os.path.join(texroot, d)
                if build_project(os.path.join(workshop, dep), out):
                    done = [k for k, v in pics.items()
                            if write_tex(v, os.path.join(out, "materials", k + ".tex"))]
                    texdir = out if done else ""
        prev = j.get("preview") or ""
        prev = os.path.join(folder, prev) if prev else ""
        if prev and not os.path.exists(prev):
            prev = ""
        title = str(j.get("title") or d).replace("\t", " ").strip()
        typ = str(source.get("type") or "").lower()
        rows.append((title, d, typ, prev, base, props, texdir))
    rows.sort(key=lambda r: r[0].lower())
    return rows, skipped


def main():
    if len(sys.argv) not in (2, 3):
        sys.exit("usage: wpe-scan.py <workshop-dir> [<texture-root>]")
    rows, skipped = scan(sys.argv[1], sys.argv[2] if len(sys.argv) == 3 else None)
    print("SKIPPED\t%d" % skipped)
    for title, d, typ, prev, base, props, texdir in rows:
        print("\t".join(("ITEM", d, typ, prev, base, json.dumps(props), texdir, title)))


if __name__ == "__main__":
    main()
