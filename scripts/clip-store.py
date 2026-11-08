#!/usr/bin/env python3
"""Record ONE clipboard change. Invoked by `wl-paste --watch`, once per change.

    wl-paste --watch python3 clip-store.py

The clipboard's contents arrive on STDIN; the mime types are read back from the
compositor. This writes the payload to a file, prepends a small record to
index.json, prunes to the cap, and prints one line on stdout so the shell knows
to re-read the index.

── Why the shell owns a clipboard store at all ────────────────────────────────
Nothing on this system records clipboard history — no cliphist, no clipman. The
alternative was installing one, and the deciding factor was IMAGES: cliphist
keeps payloads inside a bbolt database, so every image thumbnail the panel draws
would cost a `cliphist decode` subprocess, on every list refresh. Here an image
is already a file on disk, so the panel points an `Image` at it and stops. No
new package either — wl-clipboard was already installed.

── Why wl-paste and not Quickshell's native clipboardText ────────────────────
Quickshell exposes `Quickshell.clipboardText` with a change signal, and it is the
obvious choice until you notice it is Qt's QClipboard: on Wayland that reads
through wl_data_device, which only serves the FOCUSED client. A bar has no focus
almost always. `wl-paste` uses the wlr-data-control protocol, which is precisely
the "privileged listener" case — verified here by reading the live clipboard from
an unfocused process. It is also the only one of the two that can see images.

── Stdout is a signal, not data ──────────────────────────────────────────────
The one line printed on success is how services/Clipboard.qml learns the store
changed. It could have watched index.json with an inotify FileView instead, and
that was the first design — but the index is replaced by atomic rename, which
swaps the inode out from under a watch on the file. Reporting up the pipe we
already own is exact, and keeps the atomic write.
"""

import hashlib
import json
import os
import subprocess
import sys
import time

CACHE = os.environ.get("XDG_CACHE_HOME") or os.path.join(os.path.expanduser("~"), ".cache")
STORE = os.path.join(CACHE, "quicktest", "clipboard")
DATA = os.path.join(STORE, "data")
INDEX = os.path.join(STORE, "index.json")

# How many entries survive. Beyond this the oldest are dropped and their payload
# files deleted. 200 is roughly a week of ordinary copying and keeps index.json
# small enough that re-parsing it on every change is free.
MAX_ENTRIES = 200

# Anything larger is recorded but NOT stored. Copying a video file's contents or a
# huge buffer would otherwise fill the cache silently.
MAX_BYTES = 12 * 1024 * 1024

# How much text the index carries for display. The full text always lives in its
# own file — putting it here instead would mean re-parsing megabytes of JSON on
# every clipboard change to render a two-line preview.
PREVIEW_CHARS = 400

IMAGE_EXT = {
    "image/png": ".png",
    "image/jpeg": ".jpg",
    "image/jpg": ".jpg",
    "image/gif": ".gif",
    "image/webp": ".webp",
    "image/bmp": ".bmp",
    "image/tiff": ".tiff",
    "image/x-icon": ".ico",
    "image/svg+xml": ".svg",
}


def clipboard_types():
    """Mime types the current clipboard offers, lowercased."""
    try:
        out = subprocess.run(
            ["wl-paste", "--list-types"],
            capture_output=True, text=True, timeout=5,
        ).stdout
    except Exception:                                           # noqa: BLE001
        return []
    return [t.strip().lower() for t in out.splitlines() if t.strip()]


def is_secret(types):
    """Password managers flag their offer so history tools skip it.

    KeePassXC, Bitwarden and friends add `x-kde-passwordManagerHint` to the
    clipboard offer for exactly this purpose. Honouring it is the difference
    between a clipboard history and a plaintext password log. Matched loosely:
    the convention is the hint's PRESENCE, and the prefix varies by toolkit.
    """
    return any("passwordmanagerhint" in t or "concealed" in t for t in types)


def pick_image_mime(types):
    """The image type to record, or "" when this is not an image.

    A text offer WINS even when an image type is also present. Browsers offer
    image/png alongside text/html for a copied image, and applications offer
    text/plain alongside a private type for ordinary text — treating "any image
    type present" as an image would turn most copies into unreadable blobs.
    """
    if any(t.startswith("text/") for t in types):
        return ""
    for t in types:
        if t in IMAGE_EXT:
            return t
    for t in types:
        if t.startswith("image/"):
            return t
    return ""


def image_size(data):
    """(width, height) read from the file HEADER, or (0, 0) if unrecognised.

    Recorded at capture time because the obvious QML route does not work: an `Image`
    with `sourceSize` set as a decode cap reads that property back as THE CAP, not as
    the picture's real size — measured, an 88px-capped 1920x1080 PNG reports 88x88. The
    only way to get true dimensions in QML is to decode the image at full size, which
    for a 4K screenshot is 30MB of pixmap to render a 44px tile.

    Reading the header costs a few bytes and happens once per copy instead of once per
    render. It also lets the preview reserve the right height BEFORE the image loads,
    so opening one doesn't jolt the list.

    Header layouts only — no decoding, no Pillow (which is not a dependency here).
    """
    try:
        # PNG: 8-byte signature, then an IHDR chunk whose first 8 bytes are w,h (BE).
        if data[:8] == b"\x89PNG\r\n\x1a\n" and data[12:16] == b"IHDR":
            return (int.from_bytes(data[16:20], "big"),
                    int.from_bytes(data[20:24], "big"))

        # GIF: 'GIF87a'/'GIF89a', then logical screen w,h (LE).
        if data[:6] in (b"GIF87a", b"GIF89a"):
            return (int.from_bytes(data[6:8], "little"),
                    int.from_bytes(data[8:10], "little"))

        # BMP: 'BM', DIB header carries w,h (LE, signed — height is negative for
        # top-down bitmaps, which is a storage direction, not a negative size).
        if data[:2] == b"BM":
            return (int.from_bytes(data[18:22], "little", signed=True),
                    abs(int.from_bytes(data[22:26], "little", signed=True)))

        # WEBP: RIFF container, three sub-formats.
        if data[:4] == b"RIFF" and data[8:12] == b"WEBP":
            fmt = data[12:16]
            if fmt == b"VP8X":
                return (1 + int.from_bytes(data[24:27], "little"),
                        1 + int.from_bytes(data[27:30], "little"))
            if fmt == b"VP8 ":
                return (int.from_bytes(data[26:28], "little") & 0x3FFF,
                        int.from_bytes(data[28:30], "little") & 0x3FFF)
            if fmt == b"VP8L":
                bits = int.from_bytes(data[21:25], "little")
                return (1 + (bits & 0x3FFF), 1 + ((bits >> 14) & 0x3FFF))

        # JPEG: walk the segment chain to a Start-Of-Frame marker, which is the only
        # place the dimensions live. Skipping by segment length rather than scanning
        # for bytes — 0xFFC0 occurs inside compressed data often enough to matter.
        if data[:2] == b"\xff\xd8":
            i, n = 2, len(data)
            while i + 9 < n:
                if data[i] != 0xFF:
                    i += 1
                    continue
                marker = data[i + 1]
                if marker in (0xD8, 0x01) or 0xD0 <= marker <= 0xD7:
                    i += 2
                    continue
                seg = int.from_bytes(data[i + 2:i + 4], "big")
                # SOF0..SOF15, minus the markers in that range that are not frames.
                if 0xC0 <= marker <= 0xCF and marker not in (0xC4, 0xC8, 0xCC):
                    return (int.from_bytes(data[i + 7:i + 9], "big"),
                            int.from_bytes(data[i + 5:i + 7], "big"))
                if seg <= 0:
                    break
                i += 2 + seg
    except Exception:                                           # noqa: BLE001
        pass
    return (0, 0)


def read_index():
    try:
        with open(INDEX, "r", encoding="utf-8") as fh:
            data = json.load(fh)
        return data if isinstance(data, list) else []
    except FileNotFoundError:
        return []
    except Exception:                                           # noqa: BLE001
        # A corrupt index must not stop the clipboard working. Starting over
        # loses history; refusing to store loses history AND stays broken.
        return []


def write_index(entries):
    """Replace index.json atomically.

    A partial index is worse than a stale one: the panel parses this file, and a
    half-written array is a hard parse error rather than a missing entry.
    """
    tmp = INDEX + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(entries, fh, ensure_ascii=False)
        fh.flush()
        os.fsync(fh.fileno())
    os.replace(tmp, INDEX)


def prune_orphans(entries):
    """Delete payload files no entry refers to any more.

    Payloads are named by content hash, so two entries can never share a file by
    accident — but a pruned entry's file would linger forever without this.
    """
    keep = {os.path.basename(e.get("file", "")) for e in entries}
    try:
        for name in os.listdir(DATA):
            if name not in keep:
                try:
                    os.unlink(os.path.join(DATA, name))
                except OSError:
                    pass
    except FileNotFoundError:
        pass


def main():
    data = sys.stdin.buffer.read()
    if not data or not data.strip():
        return 0

    types = clipboard_types()
    if is_secret(types):
        return 0

    if len(data) > MAX_BYTES:
        print("SKIP toolarge", flush=True)
        return 0

    os.makedirs(DATA, exist_ok=True)

    image_mime = pick_image_mime(types)
    digest = hashlib.sha256(data).hexdigest()[:16]

    width = height = 0
    if image_mime:
        kind = "image"
        ext = IMAGE_EXT.get(image_mime, ".bin")
        preview = ""
        lines = 0
        width, height = image_size(data)
    else:
        kind = "text"
        ext = ".txt"
        text = data.decode("utf-8", errors="replace")
        preview = text[:PREVIEW_CHARS]
        lines = text.count("\n") + 1

    path = os.path.join(DATA, digest + ext)
    if not os.path.exists(path):
        # Named by hash, so identical content re-copied reuses the file it wrote
        # the first time — no duplicate megabyte on disk for a re-copied image.
        with open(path, "wb") as fh:
            fh.write(data)

    entries = read_index()

    # Re-copying something already in history MOVES it to the top rather than
    # adding a second row. That is also what makes copy-from-the-panel safe: it
    # puts the text back on the clipboard, which fires this script again, and
    # without the dedupe every paste would grow the list.
    entries = [e for e in entries if e.get("hash") != digest]

    entries.insert(0, {
        "hash": digest,
        "kind": kind,
        "mime": image_mime or "text/plain",
        "file": path,
        "bytes": len(data),
        "at": int(time.time()),
        "preview": preview,
        "lines": lines,
        "w": width,
        "h": height,
    })

    dropped = entries[MAX_ENTRIES:]
    entries = entries[:MAX_ENTRIES]

    write_index(entries)
    if dropped:
        prune_orphans(entries)

    print("STORED " + digest, flush=True)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:                                    # noqa: BLE001
        # Never die noisily: this runs under wl-paste --watch, and a traceback
        # per clipboard change would flood the shell's log with something the
        # user cannot act on. One line, and the clipboard keeps working.
        print("ERROR " + str(exc).replace("\n", " "), file=sys.stderr, flush=True)
        sys.exit(1)
