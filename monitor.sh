#!/usr/bin/env bash
# monitor.sh - entry point. Runs all checks, logs results, sends alerts.
#
# Usage:
#   ./monitor.sh                 run all checks, print + log + alert
#   ./monitor.sh --quiet         no stdout (for cron)
#   ./monitor.sh --report [FILE] run checks, then write the HTML report
#   ./monitor.sh --config PATH   use a different monitor.conf
#   ./monitor.sh --test          TEST_MODE: alert channels print instead of send
#
# Exit code: 0 = all OK, 1 = at least one WARN, 2 = at least one CRIT.

set -u
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

QUIET=no DO_REPORT=no TEST_MODE=no REPORT_FILE=""
CONFIG_FILE="$BASE_DIR/config/monitor.conf"
while [ $# -gt 0 ]; do
    case "$1" in
        --quiet)  QUIET=yes ;;
        --report) DO_REPORT=yes; [ "${2:-}" ] && [ "${2#--}" = "$2" ] && { REPORT_FILE="$2"; shift; } ;;
        --config) shift; CONFIG_FILE="$1" ;;
        --test)   TEST_MODE=yes ;;
        -h|--help) grep '^#' "$0" | head -n 12; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 64 ;;
    esac
    shift
done
export TEST_MODE

# --- configuration -----------------------------------------------------------
# shellcheck disable=SC1090
[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"
SECRETS_FILE="$(dirname "$CONFIG_FILE")/secrets.env"
# shellcheck disable=SC1090
[ -f "$SECRETS_FILE" ] && . "$SECRETS_FILE"

LOG_DIR="${LOG_DIR:-$BASE_DIR/logs}"
STATE_DIR="${STATE_DIR:-$BASE_DIR/state}"
mkdir -p "$LOG_DIR" "$STATE_DIR"
METRICS_LOG="$LOG_DIR/metrics.csv"
EVENT_LOG="$LOG_DIR/events.log"

# --- logging -----------------------------------------------------------------
log_line() {  # LEVEL COMPONENT MESSAGE
    printf '%s [%s] %s: %s\n' "$(date '+%F %T')" "$1" "$2" "$3" >> "$EVENT_LOG"
}

# --- libraries ---------------------------------------------------------------
. "$BASE_DIR/lib/checks.sh"
. "$BASE_DIR/lib/alerts.sh"
. "$BASE_DIR/lib/report.sh"

# --- run ---------------------------------------------------------------------
run_checks() {
    check_cpu
    check_load
    check_memory
    check_disk
    check_inodes
    check_services
}

exit_code=0
ts="$(date '+%F %T')"
while IFS=$'\t' read -r metric value status message; do
    [ -n "$metric" ] || continue
    # metrics.csv: timestamp,metric,value,status,message
    printf '%s,%s,%s,%s,%s\n' "$ts" "$metric" "$value" "$status" \
        "$(echo "$message" | tr ',' ';')" >> "$METRICS_LOG"

    [ "$QUIET" = "no" ] && printf '%-7s %s\n' "$status" "$message"

    case "$status" in
        WARN)
            [ "$exit_code" -lt 1 ] && exit_code=1
            dispatch_alert "$metric" "$status" "$message" ;;
        CRIT)
            exit_code=2
            dispatch_alert "$metric" "$status" "$message" ;;
    esac
done < <(run_checks)

if [ "$DO_REPORT" = "yes" ]; then
    REPORT_FILE="${REPORT_FILE:-$LOG_DIR/report-$(date +%F).html}"
    generate_report "$REPORT_FILE"
    [ "$QUIET" = "no" ] && echo "Report written to $REPORT_FILE"
fi

exit "$exit_code"
