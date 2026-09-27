#!/usr/bin/env bash
# install.sh - install server-monitoring + schedule it.
#
#   ./install.sh                 install for your user (no sudo needed)
#   sudo ./install.sh --system   install system-wide under /opt
#   ./install.sh --method systemd   schedule with a systemd timer instead of cron
#   ./install.sh --dry-run       show what would happen, change nothing
#
# Default schedule: checks every 5 minutes, HTML report daily at 23:55.

set -eu
MODE=user METHOD=cron DRY_RUN=no
while [ $# -gt 0 ]; do
    case "$1" in
        --system) MODE=system ;;
        --method) shift; METHOD="$1" ;;
        --dry-run) DRY_RUN=yes ;;
        -h|--help) grep '^#' "$0" | head -n 9; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 64 ;;
    esac
    shift
done

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ "$MODE" = system ]; then
    PREFIX=/opt/server-monitoring
    CONF_DIR=/etc/server-monitoring
    LOG_DIR=/var/log/server-monitoring
    UNIT_DIR=/etc/systemd/system
else
    PREFIX="$HOME/.local/share/server-monitoring"
    CONF_DIR="$HOME/.config/server-monitoring"
    LOG_DIR="$HOME/.local/state/server-monitoring/logs"
    UNIT_DIR="$HOME/.config/systemd/user"
fi
STATE_DIR="$(dirname "$LOG_DIR")/state"

run() { echo "+ $*"; [ "$DRY_RUN" = no ] && eval "$@"; }

echo "Installing server-monitoring ($MODE mode, $METHOD scheduling)"

# 1. Copy the program.
run "mkdir -p '$PREFIX' '$CONF_DIR' '$LOG_DIR' '$STATE_DIR'"
run "cp -r '$SRC/monitor.sh' '$SRC/lib' '$PREFIX/'"
run "chmod +x '$PREFIX/monitor.sh'"

# 2. Install config (keep an existing one; never overwrite secrets).
[ -f "$CONF_DIR/monitor.conf" ] || run "cp '$SRC/config/monitor.conf' '$CONF_DIR/'"
[ -f "$CONF_DIR/secrets.env" ]  || run "cp '$SRC/config/secrets.example.env' '$CONF_DIR/secrets.env'"
# Point the installed config at the real log/state dirs.
run "sed -i -e 's#^LOG_DIR=.*#LOG_DIR=\"$LOG_DIR\"#' \
             -e 's#^STATE_DIR=.*#STATE_DIR=\"$STATE_DIR\"#' '$CONF_DIR/monitor.conf'"

# 3. Wrapper so cron/systemd always use the installed config.
WRAPPER="$PREFIX/run.sh"
if [ "$DRY_RUN" = no ]; then
    cat > "$WRAPPER" <<WRAP
#!/usr/bin/env bash
exec "$PREFIX/monitor.sh" --config "$CONF_DIR/monitor.conf" "\$@"
WRAP
    chmod +x "$WRAPPER"
else
    echo "+ write $WRAPPER"
fi

# 4. Scheduling.
if [ "$METHOD" = systemd ]; then
    run "mkdir -p '$UNIT_DIR'"
    SVC=server-monitoring; [ "$MODE" = user ] && SVC=server-monitoring-user
    run "sed -e 's#@WRAPPER@#$WRAPPER#g' '$SRC/systemd/server-monitoring.service' > '$UNIT_DIR/$SVC.service'"
    run "sed -e 's#@SERVICE@#$SVC#g'        '$SRC/systemd/server-monitoring.timer'   > '$UNIT_DIR/$SVC.timer'"
    if [ "$MODE" = user ]; then
        run "systemctl --user daemon-reload"
        run "systemctl --user enable --now '$SVC.timer'"
    else
        run "systemctl daemon-reload"
        run "systemctl enable --now '$SVC.timer'"
    fi
else
    # Cron: replace our block between markers, keep everything else.
    MARK='# server-monitoring'
    NEW_CRON=$(mktemp)
    { crontab -l 2>/dev/null | grep -v -F "$MARK" || true
      echo "*/5 * * * * $WRAPPER --quiet $MARK"
      echo "55 23 * * * $WRAPPER --quiet --report $MARK"
    } > "$NEW_CRON"
    if [ "$DRY_RUN" = no ]; then crontab "$NEW_CRON"; else cat "$NEW_CRON"; fi
    rm -f "$NEW_CRON"
fi

echo
echo "Done. Next steps:"
echo "  1. Edit thresholds:      $CONF_DIR/monitor.conf"
echo "  2. Add alert credentials: $CONF_DIR/secrets.env"
echo "  3. Test a run:            $WRAPPER --test"
echo "  4. See the report:        $WRAPPER --report"
