#!/usr/bin/env bash
# lib/checks.sh - metric collectors.
#
# Every check prints one TSV line:
#   metric_name <TAB> value <TAB> status <TAB> human message
# status is one of: OK | WARN | CRIT | UNKNOWN
#
# Nothing here alerts or writes logs - collectors only measure.

# status_for VALUE WARN CRIT -> prints OK/WARN/CRIT
status_for() {
    awk -v v="$1" -v w="$2" -v c="$3" 'BEGIN{
        if (v+0 >= c+0) print "CRIT";
        else if (v+0 >= w+0) print "WARN";
        else print "OK";
    }'
}

# ---- CPU -----------------------------------------------------------------
# CPU usage % measured by diffing /proc/stat twice, SAMPLE_SEC seconds apart.
# /proc/stat's first "cpu" line counts jiffies spent in each state since boot:
#   user nice system idle iowait irq softirq steal
# usage = (delta_total - delta_idle) / delta_total * 100
check_cpu() {
    local sample="${CPU_SAMPLE_SEC:-1}"
    local a b i
    read -ra a <<< "$(grep '^cpu ' /proc/stat)"
    sleep "$sample"
    read -ra b <<< "$(grep '^cpu ' /proc/stat)"

    local idle_a=$(( a[4] + a[5] )) idle_b=$(( b[4] + b[5] ))
    local total_a=0 total_b=0
    for i in 1 2 3 4 5 6 7 8; do
        total_a=$(( total_a + ${a[$i]:-0} ))
        total_b=$(( total_b + ${b[$i]:-0} ))
    done

    local usage
    usage=$(awk -v t=$(( total_b - total_a )) -v i=$(( idle_b - idle_a )) \
        'BEGIN{ if (t <= 0) { print "0.0" } else { printf "%.1f", (t - i) * 100 / t } }')

    local st; st=$(status_for "$usage" "$CPU_WARN" "$CPU_CRIT")
    printf 'cpu\t%s\t%s\tCPU usage %.1f%% (warn %s%%, crit %s%%)\n' \
        "$usage" "$st" "$usage" "$CPU_WARN" "$CPU_CRIT"
}

# ---- Load average ----------------------------------------------------------
# 1-minute load average divided by the number of CPU cores.
# A ratio > 1 means processes are queuing for CPU time.
check_load() {
    local cores load1 ratio
    cores=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)
    load1=$(cut -d' ' -f1 /proc/loadavg)
    ratio=$(awk -v l="$load1" -v c="$cores" 'BEGIN{ printf "%.2f", l / (c > 0 ? c : 1) }')

    local st; st=$(status_for "$ratio" "$LOAD_WARN_PER_CORE" "$LOAD_CRIT_PER_CORE")
    printf 'load\t%s\t%s\tLoad %.2f on %s core(s) = %.2f per core (warn %.1f, crit %.1f)\n' \
        "$ratio" "$st" "$load1" "$cores" "$ratio" "$LOAD_WARN_PER_CORE" "$LOAD_CRIT_PER_CORE"
}

# ---- Memory ----------------------------------------------------------------
# Used % from /proc/meminfo: (MemTotal - MemAvailable) / MemTotal * 100.
# MemAvailable (kernel 3.14+) is what applications can actually still get,
# which is more honest than "free" because Linux caches aggressively.
check_memory() {
    local total avail usage
    total=$(awk '/^MemTotal:/     {print $2}' /proc/meminfo)
    avail=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
    usage=$(awk -v t="$total" -v a="$avail" \
        'BEGIN{ if (t <= 0) { print "0.0" } else { printf "%.1f", (t - a) * 100 / t } }')

    local st; st=$(status_for "$usage" "$MEM_WARN" "$MEM_CRIT")
    printf 'memory\t%s\t%s\tMemory used %.1f%% of %s MB (warn %s%%, crit %s%%)\n' \
        "$usage" "$st" "$usage" "$(( total / 1024 ))" "$MEM_WARN" "$MEM_CRIT"
}

# ---- Disk space -------------------------------------------------------------
# One line per real filesystem. Uses `df -P` (POSIX, one line per fs).
check_disk() {
    local -a mounts=()
    if [ -n "${DISK_MOUNTS:-}" ]; then
        read -ra mounts <<< "${DISK_MOUNTS:-}"
    else
        # Every local filesystem, minus pseudo/container filesystems.
        while read -r _ _ _ _ _ m; do mounts+=("$m"); done < <(
            df -P -x tmpfs -x devtmpfs -x squashfs -x overlay 2>/dev/null | tail -n +2
        )
    fi

    local m use_pct st
    for m in "${mounts[@]}"; do
        [ -n "$m" ] || continue
        use_pct=$(df -P "$m" 2>/dev/null | awk 'NR==2 {gsub(/%/,"",$5); print $5}')
        if [ -z "$use_pct" ]; then
            printf 'disk:%s\tNA\tUNKNOWN\tCannot read mount %s\n' "$m" "$m"
            continue
        fi
        st=$(status_for "$use_pct" "$DISK_WARN" "$DISK_CRIT")
        printf 'disk:%s\t%s\t%s\t%s is %s%% full (warn %s%%, crit %s%%)\n' \
            "$m" "$use_pct" "$st" "$m" "$use_pct" "$DISK_WARN" "$DISK_CRIT"
    done
}

# ---- Inodes -----------------------------------------------------------------
# Same mounts as check_disk, but looks at inode usage via `df -i`.
# A filesystem can have free blocks yet zero free inodes - new files then fail.
check_inodes() {
    local -a mounts=()
    if [ -n "${DISK_MOUNTS:-}" ]; then
        read -ra mounts <<< "${DISK_MOUNTS:-}"
    else
        while read -r _ _ _ _ _ m; do mounts+=("$m"); done < <(
            df -P -x tmpfs -x devtmpfs -x squashfs -x overlay 2>/dev/null | tail -n +2
        )
    fi

    local m use_pct st
    for m in "${mounts[@]}"; do
        [ -n "$m" ] || continue
        use_pct=$(df -Pi "$m" 2>/dev/null | awk 'NR==2 {gsub(/%/,"",$5); print $5}')
        if [ -z "$use_pct" ] || [ "$use_pct" = "-" ]; then
            continue  # pseudo filesystems report no inode table
        fi
        st=$(status_for "$use_pct" "$INODE_WARN" "$INODE_CRIT")
        printf 'inode:%s\t%s\t%s\t%s inode usage %s%% (warn %s%%, crit %s%%)\n' \
            "$m" "$use_pct" "$st" "$m" "$use_pct" "$INODE_WARN" "$INODE_CRIT"
    done
}

# ---- Services ---------------------------------------------------------------
# Asks systemd whether each configured unit is active. Degrades to UNKNOWN on
# machines without a running systemd (containers, WSL) instead of crashing.
check_services() {
    if ! command -v systemctl >/dev/null 2>&1; then
        printf 'services\tNA\tUNKNOWN\tsystemctl not installed; service checks skipped\n'
        return
    fi
    if ! systemctl is-system-running >/dev/null 2>&1; then
        printf 'services\tNA\tUNKNOWN\tsystemd is not running here; service checks skipped\n'
        return
    fi

    local svc active st msg
    for svc in ${SERVICES:-}; do
        active=$(systemctl is-active "$svc" 2>/dev/null || true)
        case "$active" in
            active)  st="OK";   msg="service $svc is active" ;;
            *)       st="CRIT"; msg="service $svc is ${active:-not found}" ;;
        esac
        printf 'service:%s\t%s\t%s\t%s\n' "$svc" "$active" "$st" "$msg"
    done
}

# ---- Top processes (for the report, not for alerting) -----------------------
top_processes() {
    ps -eo pid,comm,%cpu,%mem --sort=-%cpu 2>/dev/null | head -n 6
}
