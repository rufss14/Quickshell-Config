#!/usr/bin/env bash
# tablet-access.sh: let the logged-in user read a drawing tablet's pen and express keys.
#
#   tablet-access.sh --status      installed | absent. Needs no root.
#   tablet-access.sh --print-rule  the udev rule, as it would be written. Needs no root.
#   tablet-access.sh --install     write the rule and re-apply it to the tablets that are plugged in
#   tablet-access.sh --remove      delete the rule and re-apply
#
# Why a rule. /dev/input/event* belong to root:input, and a tablet's nodes carry no per-user access, so
# scripts/tablet-helper.py (the live pen and the express keys) cannot open them. systemd's `uaccess` tag
# grants the user who is sitting at the seat read and write on a node while they are logged in, with no
# `input` group membership (which would also let any program of theirs read every keyboard). The rule
# tags only tablets (`ID_INPUT_TABLET`, set by udev's own input_id) and nothing else.
#
# Everything that needs root runs in ONE elevated shell, so one password or one polkit dialog covers the
# write and the reload. Its script is a fixed literal; the paths reach it as arguments, never inside it.
#   already root         nothing
#   a terminal           sudo (prompts normally)
#   otherwise (no tty)   pkexec (the shell's own polkit agent shows the dialog)
set -euo pipefail

RULE_DIR="${QUICKTEST_UDEV_DIR:-/etc/udev/rules.d}"
RULE="$RULE_DIR/70-quicktest-tablet.rules"

rule_text() {
    cat <<'EOF'
# Quicktest: lets the user at the seat read a drawing tablet (the live pen and the express keys in the
# shell's Tablet page) without joining the `input` group. Written by scripts/tablet-access.sh.
SUBSYSTEM=="input", ENV{ID_INPUT_TABLET}=="1", TAG+="uaccess"
EOF
}

if   [ "$(id -u)" -eq 0 ]; then AS_ROOT=()
elif [ -t 0 ];             then AS_ROOT=(sudo)
else                            AS_ROOT=(pkexec)
fi

# One line the shell's page can show when it fails.
die() { echo "tablet-access: $*" >&2; exit 1; }

# Re-apply to tablets only: `change` is what makes logind hand out the ACL, and matching on the property
# keeps keyboards and mice out of it.
REAPPLY='udevadm control --reload-rules && udevadm trigger --subsystem-match=input --property-match=ID_INPUT_TABLET=1 --action=change'

case "${1:-}" in
    --status)
        if [ -f "$RULE" ]; then echo installed; else echo absent; fi
        ;;
    --print-rule)
        rule_text
        ;;
    --install)
        command -v udevadm >/dev/null 2>&1 || die "udevadm is missing (it is part of systemd)"
        tmp="$(mktemp)"
        trap 'rm -f "$tmp"' EXIT
        rule_text > "$tmp"
        "${AS_ROOT[@]}" sh -c 'install -D -m 0644 "$1" "$2" && '"$REAPPLY" sh "$tmp" "$RULE" \
            || die "could not install $RULE"
        echo "Installed $RULE"
        ;;
    --remove)
        command -v udevadm >/dev/null 2>&1 || die "udevadm is missing (it is part of systemd)"
        "${AS_ROOT[@]}" sh -c 'rm -f "$1" && '"$REAPPLY" sh "$RULE" || die "could not remove $RULE"
        echo "Removed $RULE"
        ;;
    *)
        die "usage: tablet-access.sh --status | --print-rule | --install | --remove"
        ;;
esac
