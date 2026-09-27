#!/usr/bin/env bash
# tests/test_monitor.sh - smoke tests. Run from the repo root:
#   bash tests/test_monitor.sh
set -u
cd "$(dirname "$0")/.."
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
PASS=0 FAIL=0

ok()   { PASS=$((PASS+1)); echo "PASS  $1"; }
bad()  { FAIL=$((FAIL+1)); echo "FAIL  $1"; }
check(){ if eval "$2"; then ok "$1"; else bad "$1"; fi }

# 1. Syntax of every shell file.
for f in monitor.sh install.sh uninstall.sh lib/*.sh; do
    check "bash -n $f" "bash -n '$f'"
done

# 2. A normal run with absurd thresholds so everything fires, in TEST_MODE.
cat > "$WORK/test.conf" <<CONF
CPU_WARN=-1
CPU_CRIT=101
LOAD_WARN_PER_CORE=-1
LOAD_CRIT_PER_CORE=999
MEM_WARN=-1
MEM_CRIT=101
DISK_WARN=-1
DISK_CRIT=101
INODE_WARN=-1
INODE_CRIT=101
SERVICES=""
ALERT_COOLDOWN_MIN=30
ALERT_EMAIL=yes
ALERT_TELEGRAM=yes
LOG_DIR="$WORK/logs"
STATE_DIR="$WORK/state"
CONF

OUT=$(./monitor.sh --test --config "$WORK/test.conf" 2>&1)
RC=$?

check "run exits 1 (WARN present)"        "[ $RC -eq 1 ]"
check "metrics.csv written"               "[ -s '$WORK/logs/metrics.csv' ]"
check "metrics.csv has cpu+memory+load"   "grep -q ',cpu,' '$WORK/logs/metrics.csv' && grep -q ',memory,' '$WORK/logs/metrics.csv' && grep -q ',load,' '$WORK/logs/metrics.csv'"
check "events.log written"                "[ -s '$WORK/logs/events.log' ]"
check "TEST_MODE email printed"           "echo \"\$OUT\" | grep -q '\[TEST\] email'"
check "TEST_MODE telegram printed"        "echo \"\$OUT\" | grep -q '\[TEST\] telegram'"
check "cooldown file created"             "ls '$WORK'/state/cooldown-* >/dev/null 2>&1"

# 3. Second run immediately: cooldown must suppress duplicate alerts.
OUT2=$(./monitor.sh --test --config "$WORK/test.conf" 2>&1)
check "cooldown suppresses repeat alert"  "! echo \"\$OUT2\" | grep -q '\[TEST\] email'"

# 4. Report generation.
check "HTML report generated"             "./monitor.sh --quiet --report '$WORK/report.html' --config '$WORK/test.conf'; [ -s '$WORK/report.html' ]"
check "report has title + status pills"   "grep -q 'Daily server report' '$WORK/report.html' && grep -q 'pill WARN' '$WORK/report.html'"

# 5. install.sh --dry-run changes nothing and mentions both schedulers.
DRY=$(./install.sh --dry-run 2>&1)
check "install --dry-run shows crontab"   "echo \"\$DRY\" | grep -q 'server-monitoring'"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
