#!/usr/bin/env bash
# lib/alerts.sh - notification channels + cooldown bookkeeping.
#
# Credentials come from config/secrets.env (sourced by monitor.sh).
# TEST_MODE=yes makes every channel print instead of sending.

# alert_key_allowed KEY -> exit 0 if we may alert for KEY now.
# Uses one state file per key; the file's mtime is the last alert time.
alert_key_allowed() {
    local key="$1" f now last
    f="$STATE_DIR/cooldown-$(echo "$key" | tr -c 'a-zA-Z0-9._-' '_')"
    now=$(date +%s)
    if [ -f "$f" ]; then
        last=$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f")
        if [ $(( now - last )) -lt $(( ALERT_COOLDOWN_MIN * 60 )) ]; then
            return 1
        fi
    fi
    mkdir -p "$STATE_DIR"
    : > "$f"
    return 0
}

send_email() {
    local subject="$1" body="$2"
    if [ "$ALERT_EMAIL" != "yes" ]; then return 0; fi
    if [ "${TEST_MODE:-no}" = "yes" ]; then
        echo "[TEST] email to ${EMAIL_TO:-?}: $subject"
        return 0
    fi
    if ! command -v mail >/dev/null 2>&1; then
        log_line "WARN" "ALERT" "ALERT_EMAIL=yes but 'mail' command not found"
        return 1
    fi
    printf '%s\n' "$body" | mail -s "$subject" -r "${EMAIL_FROM:-monitor@$(hostname)}" "$EMAIL_TO"
}

send_telegram() {
    local text="$1"
    if [ "$ALERT_TELEGRAM" != "yes" ]; then return 0; fi
    if [ "${TEST_MODE:-no}" = "yes" ]; then
        echo "[TEST] telegram: $text"
        return 0
    fi
    if [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
        log_line "WARN" "ALERT" "ALERT_TELEGRAM=yes but token/chat id missing in secrets.env"
        return 1
    fi
    curl -sS --max-time 10 \
        -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TELEGRAM_CHAT_ID}" \
        --data-urlencode "text=${text}" >/dev/null
}

# dispatch_alert METRIC STATUS MESSAGE
# Honours the per-metric cooldown, then fans out to every enabled channel.
dispatch_alert() {
    local metric="$1" status="$2" message="$3"
    alert_key_allowed "$metric" || return 0

    local host; host=$(hostname)
    local subject="[$status] $host: $metric"
    local body="$message
Host: $host
Time: $(date '+%F %T %z')
Metric: $metric"

    send_email "$subject" "$body"
    send_telegram "$subject - $message"
    log_line "ALERT" "$metric" "$message"
}
