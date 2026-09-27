#!/usr/bin/env bash
# Runs only on a disposable Ubuntu GitHub Actions VM. Uses real systemd and cron.
set -euo pipefail
cd "$(dirname "$0")/.."
if [ "$(id -u)" -ne 0 ] || [ "$(ps -p 1 -o comm= | tr -d ' ')" != systemd ]; then
    echo 'This test requires root on a systemd host' >&2; exit 1
fi
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq cron curl >/dev/null
systemctl enable --now cron
systemctl is-active --quiet cron
TMP=$(mktemp -d)
chmod 755 "$TMP"
cleanup() {
    systemctl stop server-monitoring.timer ci-monitor.service 2>/dev/null || true
    rm -f /etc/systemd/system/server-monitoring.timer.d/ci-interval.conf \
          /etc/systemd/system/ci-monitor.service
    rmdir /etc/systemd/system/server-monitoring.timer.d 2>/dev/null || true
    systemctl daemon-reload
    crontab -u runner -r 2>/dev/null || true
    rm -rf "$TMP"
}
trap cleanup EXIT

# Actual installation; no dry-run. The installed wrapper must produce real logs.
./install.sh --system --method systemd
systemctl is-enabled --quiet server-monitoring.timer
systemctl is-active --quiet server-monitoring.timer
test -x /opt/server-monitoring/run.sh
test -f /etc/server-monitoring/monitor.conf
/opt/server-monitoring/run.sh --test > "$TMP/initial.txt" || test "$?" -le 2
test -s /var/log/server-monitoring/metrics.csv
/opt/server-monitoring/run.sh --test --report "$TMP/report.html" > /dev/null || test "$?" -le 2
grep -q 'Daily server report' "$TMP/report.html"
echo 'PASS: real system-wide install, wrapper, metrics and report'

# Test one genuinely running service and one stopped service. An inactive unit
# has a distinct CRIT row, rather than an UNKNOWN 'systemd unavailable' row.
cat > /etc/systemd/system/ci-monitor.service <<'UNIT'
[Unit]
Description=Disposable monitoring integration target
[Service]
Type=simple
ExecStart=/usr/bin/sleep infinity
UNIT
systemctl daemon-reload
systemctl start ci-monitor.service
systemctl is-active --quiet ci-monitor.service
cp /etc/server-monitoring/monitor.conf "$TMP/targets.conf"
sed -i 's/^SERVICES=.*/SERVICES="cron ci-monitor.service"/' "$TMP/targets.conf"
/opt/server-monitoring/run.sh --config "$TMP/targets.conf" --test > "$TMP/active.txt" || test "$?" -le 2
grep -q 'OK.*service cron is active' "$TMP/active.txt"
grep -q 'OK.*service ci-monitor.service is active' "$TMP/active.txt"
systemctl stop ci-monitor.service
set +e
/opt/server-monitoring/run.sh --config "$TMP/targets.conf" --test > "$TMP/stopped.txt"
rc=$?
set -e
test "$rc" -eq 2
grep -q 'CRIT.*service ci-monitor.service is inactive' "$TMP/stopped.txt"
echo 'PASS: live systemd active and stopped service checks'

# Force a real WARN and CRIT without stressing this shared VM. Simulated alerts
# only: no mail or Telegram traffic or credentials. Separate state avoids cooldown.
cp "$TMP/targets.conf" "$TMP/forced.conf"
cat >> "$TMP/forced.conf" <<CONF
CPU_WARN=-1
CPU_CRIT=101
MEM_WARN=-1
MEM_CRIT=0
ALERT_COOLDOWN_MIN=30
ALERT_EMAIL=yes
ALERT_TELEGRAM=yes
LOG_DIR="$TMP/forced-logs"
STATE_DIR="$TMP/forced-state"
CONF
set +e
/opt/server-monitoring/run.sh --test --config "$TMP/forced.conf" > "$TMP/forced.txt"
rc=$?
set -e
test "$rc" -eq 2
grep -q '^WARN.*CPU usage' "$TMP/forced.txt"
grep -q '^CRIT.*Memory used' "$TMP/forced.txt"
grep -q '\[TEST\] email' "$TMP/forced.txt"
grep -q '\[TEST\] telegram' "$TMP/forced.txt"
test -s "$TMP/forced-logs/events.log"
/opt/server-monitoring/run.sh --test --config "$TMP/forced.conf" > "$TMP/repeat.txt" || test "$?" -eq 2
! grep -q '\[TEST\]' "$TMP/repeat.txt"
echo 'PASS: forced WARN/CRIT, simulated email/Telegram, cooldown'

# Wizard uses stdin defaults plus explicit final yes; writes only test copy.
cp /etc/server-monitoring/monitor.conf "$TMP/wizard.conf"
python3 setup.py --config "$TMP/wizard.conf" < <(printf '\n%.0s' {1..12}; printf 'yes\n') > "$TMP/wizard.txt"
grep -q 'Saved ' "$TMP/wizard.txt"
grep -q '^CPU_WARN=80$' "$TMP/wizard.conf"
echo 'PASS: wizard noninteractive stdin flow'

# Actual systemd timer fire, shortened ONLY on this disposable runner via a
# temporary drop-in; production timer template remains unchanged.
mkdir -p /etc/systemd/system/server-monitoring.timer.d
cat > /etc/systemd/system/server-monitoring.timer.d/ci-interval.conf <<'TIMER'
[Timer]
OnBootSec=
OnUnitActiveSec=
OnActiveSec=5s
AccuracySec=1s
TIMER
systemctl daemon-reload
systemctl restart server-monitoring.timer
before=$(wc -l < /var/log/server-monitoring/metrics.csv)
fired=no
for i in {1..25}; do
    sleep 1
    after=$(wc -l < /var/log/server-monitoring/metrics.csv)
    if (( after > before )); then fired=yes; break; fi
done
test "$fired" = yes
systemctl show server-monitoring.timer -p LastTriggerUSec -p Result
echo 'PASS: real systemd timer fired and appended metrics'

# Run cron daemon and a temporary per-minute entry as unprivileged runner;
# confirm cron itself invokes the installed wrapper. Preserve installed systemd
# timer; the added cron entry is scoped to this disposable VM only.
: > "$TMP/cron-marker"
chown runner:runner "$TMP/cron-marker"
chmod 666 "$TMP/cron-marker"
cat > "$TMP/cron.conf" <<CONF
SERVICES="cron"
CPU_WARN=99
CPU_CRIT=100
LOAD_WARN_PER_CORE=1000
LOAD_CRIT_PER_CORE=2000
MEM_WARN=99
MEM_CRIT=100
DISK_WARN=99
DISK_CRIT=100
INODE_WARN=99
INODE_CRIT=100
DISK_MOUNTS="/"
ALERT_EMAIL=no
ALERT_TELEGRAM=no
LOG_DIR="$TMP/cron-logs"
STATE_DIR="$TMP/cron-state"
CONF
mkdir -p "$TMP/cron-logs" "$TMP/cron-state"
chown runner:runner "$TMP/cron-logs" "$TMP/cron-state"
chmod 644 "$TMP/cron.conf"
printf '* * * * * /opt/server-monitoring/run.sh --config %s --test --quiet >/dev/null 2>&1; test -s %s/metrics.csv && echo fired >> %s\n' "$TMP/cron.conf" "$TMP/cron-logs" "$TMP/cron-marker" | crontab -u runner -
cron_fired=no
for i in {1..75}; do
    sleep 1
    if grep -q '^fired$' "$TMP/cron-marker"; then cron_fired=yes; break; fi
done
test "$cron_fired" = yes
echo 'PASS: real cron daemon fired and invoked installed wrapper'

python3 dashboard/app.py --metrics /var/log/server-monitoring/metrics.csv --port 8765 > "$TMP/dashboard.log" 2>&1 &
dash_pid=$!
trap 'kill "$dash_pid" 2>/dev/null || true; cleanup' EXIT
for i in {1..15}; do
    if curl --fail --silent http://127.0.0.1:8765/healthz > "$TMP/healthz"; then break; fi
    sleep 1
done
grep -qx ok "$TMP/healthz"
curl --fail --silent http://127.0.0.1:8765/ > "$TMP/dashboard.html"
grep -q 'Server Pulse' "$TMP/dashboard.html"
grep -q 'CPU usage' "$TMP/dashboard.html"
grep -q 'service:' "$TMP/dashboard.html"
echo 'PASS: localhost dashboard HTTP healthz and real metrics rendering'
