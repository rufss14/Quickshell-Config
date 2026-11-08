#!/usr/bin/env bash
# ── test-restore-hypr.sh ──────────────────────────────────────────────────────
# scripts/restore-hypr-config.sh against a throwaway XDG_CONFIG_HOME. Safe: it never looks at the real config.
#     bash scripts/test-restore-hypr.sh
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
S="$HERE/restore-hypr-config.sh"
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "  FAIL  $1"; echo "        got  [$2]"; echo "        want [$3]"; fi; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export XDG_CONFIG_HOME="$T"
mkdir -p "$T/hypr" "$T/hypr.bak.100" "$T/hypr.bak.200"
echo bundled > "$T/hypr/hyprland.lua"
echo old100  > "$T/hypr.bak.100/hyprland.lua"
echo old200  > "$T/hypr.bak.200/hyprland.lua"
echo mini    > "$T/hypr/quicktest.lua"
echo minibak > "$T/hypr/quicktest.lua.bak.300"
mkdir -p "$T/hypr.bak.notanumber"; echo x > "$T/hypr.bak.notanumber/a"

ok "list: newest first, ignores a non-numeric suffix" "$(bash "$S" --list | cut -d'|' -f1,3 | tr '\n' ' ')" "file|300 dir|200 dir|100 "
bash "$S" --restore >/dev/null
bash "$S" --restore "$T/hypr.bak.200" >/dev/null   # a second restore in the same second must not collide
ok "restore: two in one second keep both set-aside copies" "$(ls -d "$T"/hypr.before-restore.* | wc -l)" "2"
bash "$S" --restore >/dev/null
ok "restore: the newest backup comes back" "$(cat "$T/hypr/hyprland.lua")" "old200"
ok "restore: what was there is set aside, not deleted" "$(grep -l bundled "$T"/hypr.before-restore.*/hyprland.lua | wc -l)" "1"
ok "restore: the backup itself is untouched" "$(cat "$T/hypr.bak.200/hyprland.lua")" "old200"
bash "$S" --restore "$T/hypr.bak.100" >/dev/null
ok "restore: a named backup" "$(cat "$T/hypr/hyprland.lua")" "old100"
bash "$S" --restore "/etc" >/dev/null 2>&1; ok "restore: refuses a path that is not a backup" "$?" "2"
bash "$S" --restore "$T/hypr.bak.notanumber" >/dev/null 2>&1; ok "restore: refuses a non-numeric backup" "$?" "2"
bash "$S" --restore "$T/hypr.bak.100/../hypr.bak.100" >/dev/null 2>&1; ok "restore: refuses a path with .. in it" "$?" "2"

echo mini2 > "$T/hypr/quicktest.lua"; echo minibak > "$T/hypr/quicktest.lua.bak.300"
bash "$S" --restore-minimal >/dev/null
ok "minimal: the earlier quicktest.lua comes back" "$(cat "$T/hypr/quicktest.lua")" "minibak"
ok "minimal: the current one is set aside" "$(cat "$T"/hypr/quicktest.lua.before-restore.*)" "mini2"
echo mini3 > "$T/hypr/quicktest.lua"
rm -f "$T"/hypr/quicktest.lua.bak.*
out="$(bash "$S" --restore-minimal)"
ok "minimal: with no earlier one it is set aside and the require() is mentioned" "$([ ! -e "$T/hypr/quicktest.lua" ] && echo "$out" | grep -c 'require')" "1"

rm -rf "$T/hypr.bak."*
bash "$S" --restore >/dev/null 2>&1; ok "restore: with no backup it says so" "$?" "1"
ok "list: no backups at all is not an error" "$(bash "$S" --list >/dev/null; echo $?)" "0"
bash "$S" --nonsense >/dev/null 2>&1; ok "an unknown argument is refused" "$?" "2"

echo; echo "$pass passed, $fail failed"; [ "$fail" = 0 ]
