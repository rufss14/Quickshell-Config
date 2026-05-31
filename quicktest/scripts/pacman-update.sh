#!/usr/bin/env bash

# Load pywal colors
source "$HOME/.cache/wal/colors.sh"

BOLD="\e[1m"
RESET="\e[0m"


divider() {
  echo -e "────────────────────────────────────────────"
}

section() {
  echo
  divider
  echo -e "${BOLD} $1 ${RESET}"
  divider
}

status() {
  echo -e "${WARN}➜ $1${RESET}"
}

ok() {
  echo -e "${GOOD}✔ $1${RESET}"
}

fail() {
  echo -e "${BAD}✖ $1${RESET}"
}

clear

section "System Update"
status "Syncing & upgrading packages..."

if sudo pacman -Syu; then
  ok "System packages updated"
else
  fail "Pacman update failed"
fi

section "Flatpak Update"
status "Updating Flatpak apps..."

if flatpak update -y; then
  ok "Flatpaks updated"
else
  fail "Flatpak update failed"
fi

echo
divider
echo -e "${BOLD}${FG} All updates complete ${RESET}"
divider
echo
read -rp "Press Enter to exit..."