#!/usr/bin/env bash
# greet-export.sh — hand the greeter the three things it is allowed to know.
#
#     scripts/greet-export.sh                 # local, for previewing greet.qml
#     sudo scripts/greet-export.sh --system   # into the greeter's own home
#
# Optional overrides: --wallpaper PATH  --avatar PATH  --user NAME  --library DIR
#
# ── Why anything has to be exported at all ────────────────────────────────────
# The greeter is a different process, run by greetd as the unprivileged `greeter`
# user, with HOME=/var/lib/greeter. Your home is 0700 on any normal install, so the
# greeter can read exactly nothing of yours — not the wallpaper, not the palette, not
# your face. The two ways out of that are to loosen permissions on your own files so
# a login screen can look prettier, or to copy the handful of things it genuinely
# needs into a place it already owns. This is the second one.
#
# ── The contract, in full ─────────────────────────────────────────────────────
#   <cache>/quickshell-greet/greet.json   { "backdrop": …, "avatar": …, "user": … }
#   <cache>/quickshell-greet/backdrop.*   a COPY of the wallpaper
#   <cache>/quickshell-greet/avatar.*     a COPY of the profile picture (optional)
#   <cache>/wal/colors.json               the palette, where config/Colors.qml
#                                         already looks — unmodified, no greeter
#                                         branch, no second code path
#
# Three fields and two pictures. Deliberately NOT your config.json: the greeter has no
# settings page to correct anything from (nobody has authenticated yet), so every
# setting it could see would be one it might act on and you could not fix from there.
#
# ── Paths are absolute and belong to the DESTINATION ──────────────────────────
# greet.json names files as the greeter will see them, which is why it is written per
# destination rather than copied. A local export points into your cache; a --system
# export points into /var/lib/greeter. Copying one to the other would produce a
# greeter that silently shows no wallpaper, because the path in it is one it cannot
# read.

set -euo pipefail

SYSTEM=0
WALLPAPER=""
AVATAR=""
USERNAME="${USER:-$(id -un)}"
# Where to resolve the marker file's FILENAME against. This is Config.wallLibraryDir,
# which the shell can't hand us — greet-export is run by hand, and under sudo at that.
# So it is a flag, with the same default the shell resolves "" to. Set it if you moved
# your library, or the greeter falls back to the export copy below.
LIBRARY="${QUICKSHELL_WALL_LIBRARY:-}"

while [ $# -gt 0 ]; do
    case "$1" in
        --system)    SYSTEM=1; shift ;;
        --wallpaper) WALLPAPER="$2"; shift 2 ;;
        --avatar)    AVATAR="$2"; shift 2 ;;
        --user)      USERNAME="$2"; shift 2 ;;
        --library)   LIBRARY="$2"; shift 2 ;;
        -h|--help)   sed -n '2,8p' "$0"; exit 0 ;;
        *)           echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

# ── Whose session are we exporting? ──────────────────────────────────────────
# Under `sudo` every one of $HOME, $USER and $XDG_CACHE_HOME belongs to root, and a
# naive read of them exports root's empty cache over the top of a working greeter.
# SUDO_USER is the one variable that still names the person who typed the command.
if [ -n "${SUDO_USER:-}" ] && [ "${SUDO_USER}" != "root" ]; then
    SRC_USER="$SUDO_USER"
    SRC_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    [ "$USERNAME" = "${USER:-}" ] && USERNAME="$SUDO_USER"
else
    SRC_USER="${USER:-$(id -un)}"
    SRC_HOME="$HOME"
fi
SRC_CACHE="${XDG_CACHE_HOME:-$SRC_HOME/.cache}"
# Under sudo, XDG_CACHE_HOME (if it survived the env) is root's.
[ -n "${SUDO_USER:-}" ] && SRC_CACHE="$SRC_HOME/.cache"

if [ "$SYSTEM" -eq 1 ]; then
    GREETER_HOME="${GREETER_HOME:-/var/lib/greeter}"
    DEST_CACHE="$GREETER_HOME/.cache"
    if [ "$(id -u)" -ne 0 ]; then
        echo "--system writes into $GREETER_HOME and needs root. Re-run with sudo." >&2
        exit 1
    fi
    if ! getent passwd greeter >/dev/null; then
        echo "No 'greeter' user on this machine — is greetd installed?" >&2
        exit 1
    fi
else
    DEST_CACHE="${XDG_CACHE_HOME:-$SRC_HOME/.cache}"
fi

DEST="$DEST_CACHE/quickshell-greet"
mkdir -p "$DEST" "$DEST_CACHE/wal"

# ── The wallpaper ─────────────────────────────────────────────────────────────
# Same two sources services/Wallpaper.qml uses, in the same order: the marker file
# records a FILENAME, resolved against the library. Read rather than guessed, so the
# greeter shows what the desktop is actually showing.
if [ -z "$WALLPAPER" ]; then
    marker="$SRC_CACHE/current_wallpaper_name"
    if [ -r "$marker" ]; then
        name=$(tr -d '\n' < "$marker")
        if [ -n "$name" ]; then
            found=$(find "${LIBRARY:-$SRC_HOME/wallpapers/walls}" \
                    -type f -name "$name" -print -quit 2>/dev/null || true)
            [ -n "$found" ] && WALLPAPER="$found"
        fi
    fi
fi

# Last resort: the stable export copy (Config.wallExportPath). It is a copy of exactly
# the image we were trying to find, so it answers the question whenever the library
# lookup above missed — which now includes the case where the library has been moved
# and this script wasn't told where to. Better a correct backdrop from a second source
# than a greeter with none because a default path was wrong.
if [ -z "$WALLPAPER" ] && [ -r "$SRC_HOME/wallpapers/pywallpaper.jpg" ]; then
    WALLPAPER="$SRC_HOME/wallpapers/pywallpaper.jpg"
fi

BACKDROP=""
if [ -n "$WALLPAPER" ] && [ -r "$WALLPAPER" ]; then
    # The extension is carried across on purpose: the greeter branches on `.gif` to
    # pick AnimatedImage over Image, and a plain Image renders frame one of a GIF and
    # then stops — which reads as a still that is subtly wrong rather than as an error.
    ext="${WALLPAPER##*.}"
    case "$ext" in
        jpg|jpeg|png|gif|webp|JPG|JPEG|PNG|GIF|WEBP) ;;
        *) ext="png" ;;
    esac
    rm -f "$DEST"/backdrop.*
    install -m 0644 "$WALLPAPER" "$DEST/backdrop.$ext"
    BACKDROP="$DEST/backdrop.$ext"
    echo "wallpaper  → $BACKDROP"
else
    echo "wallpaper  → none found (the greeter will use the palette's own colour)"
fi

# ── The profile picture ───────────────────────────────────────────────────────
# The same fallback chain the lock screen walks. Optional throughout: without one the
# greeter draws the monogram, which is a design, not a failure.
if [ -z "$AVATAR" ]; then
    for candidate in "$SRC_HOME/.face" "$SRC_HOME/.face.icon" \
                     "/var/lib/AccountsService/icons/$SRC_USER"; do
        [ -r "$candidate" ] && { AVATAR="$candidate"; break; }
    done
fi

FACE=""
if [ -n "$AVATAR" ] && [ -r "$AVATAR" ]; then
    ext="${AVATAR##*.}"
    case "$ext" in jpg|jpeg|png|webp|JPG|JPEG|PNG|WEBP) ;; *) ext="png" ;; esac
    rm -f "$DEST"/avatar.*
    install -m 0644 "$AVATAR" "$DEST/avatar.$ext"
    FACE="$DEST/avatar.$ext"
    echo "avatar     → $FACE"
else
    echo "avatar     → none (monogram)"
fi

# ── The palette ───────────────────────────────────────────────────────────────
# Copied to the path config/Colors.qml already reads, so the greeter gets the
# wallpaper-derived scheme with no greeter-specific branch anywhere in the palette
# code. Without it the greeter wears the shell's monochrome fallback (PaletteRoles),
# not the user's colours.
#
# Skipped entirely on a local export, where source and destination ARE the same file.
# `install` onto itself would at best be a no-op and at worst truncate it — and it
# would relax the mode of your live palette from 0600 to 0644 as a side effect of
# previewing a login screen. The copy only means anything when the destination is
# somewhere you cannot otherwise reach.
if [ "$SRC_CACHE/wal/colors.json" = "$DEST_CACHE/wal/colors.json" ]; then
    echo "palette    → already in place (local export)"
elif [ -r "$SRC_CACHE/wal/colors.json" ]; then
    install -m 0644 "$SRC_CACHE/wal/colors.json" "$DEST_CACHE/wal/colors.json"
    echo "palette    → $DEST_CACHE/wal/colors.json"
else
    echo "palette    → none found at $SRC_CACHE/wal/colors.json (built-in fallback)" >&2
fi

# ── The bundle ────────────────────────────────────────────────────────────────
# python3 rather than printf, so a path containing a quote or a backslash produces
# valid JSON instead of a file the greeter silently fails to parse. python3 is already
# a hard dependency of this config (the updater cannot run without it).
#
# The weather location rides along because services/Weather.qml reads it from Config,
# and the greeter's Config is all defaults — so without this the greeter's weather card
# has no coordinates and correctly refuses to fetch. Lifted out of the running shell's
# own config.json rather than asked for again: it is already the answer you gave the
# settings page, and two places to set your location is one place to get it wrong.
#
# Read-only, and it fails soft — no config.json, or no location in it, just means no
# weather on the greeter.
python3 - "$DEST/greet.json" "$BACKDROP" "$FACE" "$USERNAME" "$SRC_HOME" <<'PY'
import glob, json, os, sys

out, backdrop, avatar, user, home = sys.argv[1:6]

bundle = {"backdrop": backdrop, "avatar": avatar, "user": user}

# Quickshell hashes the shell's path into its state directory, so the file cannot be
# named directly — but only one of them will have a weather location in it. Newest
# wins if somehow several do.
candidates = sorted(
    glob.glob(os.path.join(home, ".local/state/quickshell/by-shell/*/config.json")),
    key=lambda p: os.path.getmtime(p), reverse=True)

for path in candidates:
    try:
        with open(path) as fh:
            cfg = json.load(fh)
    except (OSError, ValueError):
        continue
    if cfg.get("weatherPlace"):
        bundle["weatherPlace"]  = cfg["weatherPlace"]
        bundle["weatherLat"]    = cfg.get("weatherLat", 0)
        bundle["weatherLon"]    = cfg.get("weatherLon", 0)
        bundle["weatherMetric"] = cfg.get("weatherMetric", True)
        break

with open(out, "w") as f:
    json.dump(bundle, f, indent=2)
    f.write("\n")

print("weather    → %s" % (bundle.get("weatherPlace") or "not configured — card hidden"))
PY
chmod 0644 "$DEST/greet.json"
echo "user       → $USERNAME"

# ══ The shell itself ══════════════════════════════════════════════════════════
# A SNAPSHOT at $GREETER_HOME/shell, taken deliberately, rather than greetd pointing
# at your working tree.
#
# ── Why a copy and not a path into ~/.config/quicktest ────────────────────────
#   · The greeter runs as `greeter`. On a normally-permissioned system /home is 0700
#     and it can read nothing of yours, so a path into your home works on the machine
#     that set it up and on no other.
#   · More importantly: a login screen must not live-track a repo you are editing. A
#     shell that fails to load is an inconvenience at 2pm and a machine you cannot log
#     into at 2am. Moving the snapshot forward is a thing you do on purpose, once the
#     shell is known good.
#
# The whole tree, minus the exclusions below, rather than a curated subset. The import
# graph already reaches across directories (components → config, services → state) and
# a hand-picked list is one `import` away from being wrong at the worst possible time.
# It is ~4MB.
if [ "$SYSTEM" -eq 1 ]; then
    SRC_TREE="$(cd "$(dirname "$0")/.." && pwd)"
    TREE="$GREETER_HOME/shell"

    echo
    echo "shell      → $TREE (snapshot of $SRC_TREE)"

    # This `rm -rf` runs as root. GREETER_HOME comes from a ${:-default} so it cannot
    # normally be empty — but "cannot normally" is not a good enough argument for a
    # recursive delete with root's privileges, and an exported GREETER_HOME="" would
    # turn the line below into `rm -rf /shell`. Refuse anything that is not an absolute
    # path at least two levels deep.
    case "$TREE" in
        /*/*/*) ;;
        *) echo "REFUSING: '$TREE' is not a safe path to delete." >&2; exit 1 ;;
    esac
    [ -e "$TREE" ] && [ ! -d "$TREE" ] && {
        echo "REFUSING: $TREE exists and is not a directory." >&2; exit 1; }

    rm -rf "$TREE"
    mkdir -p "$TREE"

    # ── What must NOT cross into a system location ────────────────────────────
    # discord-rpc.json holds the OAuth CLIENT SECRET and is 0600 in your tree for
    # exactly that reason. Copying it here would put it under a directory the greeter
    # user owns — a different, unprivileged account — which is the whole threat model
    # of scripts/discord-credentials.py undone by a `cp`. The greeter has no Discord
    # card and never reads this file.
    #
    # state/ is CODE (UiState.qml) and is copied; the exclusions are secrets and
    # version-control noise only.
    tar -C "$SRC_TREE" -cf - \
        --exclude='./discord-rpc.json' \
        --exclude='./.git' \
        --exclude='./.gitignore' \
        . | tar -C "$TREE" -xf -

    if [ -e "$TREE/discord-rpc.json" ]; then
        echo "REFUSING: discord-rpc.json reached $TREE — aborting." >&2
        rm -rf "$TREE"
        exit 1
    fi

    # ── Normalise modes ───────────────────────────────────────────────────────
    # Some sources are 0600 in the working tree (modules/panels/WallpaperPanel.qml and
    # friends, for no reason anybody remembers). Preserved verbatim, the greeter user
    # cannot read them and Quickshell fails at load with "is not a type" — a confusing
    # error a long way from its cause. Everything here is public code by definition;
    # the secret was excluded above.
    find "$TREE" -type d -exec chmod 0755 {} +
    find "$TREE" -type f -exec chmod 0644 {} +
    find "$TREE/scripts" -type f -name '*.sh' -exec chmod 0755 {} + 2>/dev/null || true
    find "$TREE/scripts" -type f -name '*.py' -exec chmod 0755 {} + 2>/dev/null || true

    echo "           $(find "$TREE" -type f | wc -l) files"

    # ── The session's compositor config ───────────────────────────────────────
    mkdir -p /etc/greetd
    install -m 0644 "$SRC_TREE/scripts/greet-session.lua" /etc/greetd/greet-session.lua
    echo "session    → /etc/greetd/greet-session.lua"
fi

# ── Ownership ─────────────────────────────────────────────────────────────────
# Everything above was written as root. The greeter runs as `greeter` and would find
# a directory it cannot traverse — which fails exactly like having no export at all,
# only after you have already swapped greetd over to it.
if [ "$SYSTEM" -eq 1 ]; then
    chown -R greeter:greeter "$DEST" "$DEST_CACHE/wal" "$GREETER_HOME/shell"
    chmod 0755 "$GREETER_HOME" "$DEST_CACHE" "$DEST" "$DEST_CACHE/wal"
    echo
    echo "Exported into $GREETER_HOME. greetd still runs its current greeter —"
    echo "nothing about your login has changed yet. See the config.toml note below."
fi

echo
echo "Done. Preview it without touching your login:"
echo "  start-hyprland -- --config $(cd "$(dirname "$0")" && pwd)/greet-preview.lua"

# ── The last step, which this script deliberately does NOT take ──────────────
# Everything above is inert: greetd has not been told about any of it. The one edit
# that changes what happens when you boot is left to a person, because getting it
# wrong is not "the login screen looks odd", it is "this machine has no login screen".
if [ "$SYSTEM" -eq 1 ]; then
    cat <<'EOF'

── To actually switch greetd over ────────────────────────────────────────────
FIRST, take a real backup. Do not assume config.toml.bak is one: on a stock Arch
install that file is the PACKAGE DEFAULT (`agreety --cmd /bin/sh`), not a copy of
whatever you are running now. Restoring it gets you a working text login, which is a
recovery but is not "put it back how it was".

    sudo cp -n /etc/greetd/config.toml /etc/greetd/config.toml.prev

Then edit /etc/greetd/config.toml and change ONLY the command line, keeping the old
one commented directly above it so the diff is readable:

    [default_session]
    # command = "start-hyprland -- --config /etc/greetd/hyprland-greeter-config.conf"
    command = "start-hyprland -- --config /etc/greetd/greet-session.lua"
    user = "greeter"

Then, BEFORE you reboot, restart greetd while you still have a session — this is the
whole point of doing it in this order, because a greeter that fails here costs you
nothing:

    sudo systemctl restart greetd

That drops you to the greeter on VT 1. If you get a password box, log in through it
once and you are done. If you get a black screen:

    Ctrl+Alt+F2, log in on the TTY, then
    sudo cp /etc/greetd/config.toml.prev /etc/greetd/config.toml
    sudo systemctl restart greetd

Keep that TTY logged in until you have been through the new greeter successfully.
greetd restarting into a broken greeter is recoverable from a TTY and nowhere else.
EOF
fi
