#!/bin/bash
# Safe QuickShell reload
QS_BIN="quickshell"
(
# small delay so this script survives QS dying
sleep 0.3
# kill running instances
pkill -TERM quickshell 2>/dev/null
# wait until fully gone
for i in {1..40}; do
pgrep -x quickshell >/dev/null || break
sleep 0.1
done
# force kill if stubborn
pkill -9 quickshell 2>/dev/null
# brief pause to avoid race conditions
sleep 0.2
# restart detached from terminal + QS process tree
setsid "$QS_BIN" -p ~/.config/quicktest/shell.qml >/dev/null 2>&1 &
) & disown
exit 0