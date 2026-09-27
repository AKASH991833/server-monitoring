#!/usr/bin/env bash
# uninstall.sh - remove scheduled jobs and (optionally) installed files.
set -eu
MODE=user
[ "${1:-}" = "--system" ] && MODE=system

MARK='# server-monitoring'
NEW_CRON=$(mktemp)
crontab -l 2>/dev/null | grep -v -F "$MARK" > "$NEW_CRON" || true
crontab "$NEW_CRON" 2>/dev/null || true
rm -f "$NEW_CRON"
echo "Removed cron entries."

if [ "$MODE" = system ]; then
    systemctl disable --now server-monitoring.timer 2>/dev/null || true
    rm -f /etc/systemd/system/server-monitoring.{service,timer}
    systemctl daemon-reload 2>/dev/null || true
    echo "Removed systemd units. Files left in /opt/server-monitoring, /etc/server-monitoring, /var/log/server-monitoring (delete manually if unwanted)."
else
    systemctl --user disable --now server-monitoring-user.timer 2>/dev/null || true
    rm -f "$HOME/.config/systemd/user/server-monitoring-user."{service,timer}
    systemctl --user daemon-reload 2>/dev/null || true
    echo "Removed systemd user units. Files left in ~/.local/share/server-monitoring, ~/.config/server-monitoring, ~/.local/state/server-monitoring (delete manually if unwanted)."
fi
