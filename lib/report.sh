#!/usr/bin/env bash
# lib/report.sh - render the daily HTML report.
#
# Input: the metrics CSV that monitor.sh appends to ($METRICS_LOG).
# Output: a self-contained HTML file (inline CSS, no JS, no network).

html_escape() {
    sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

# generate_report OUTPUT_FILE
generate_report() {
    local out="$1" host now
    host=$(hostname)
    now=$(date '+%F %T %z')

    # Latest line per metric from today's metrics log.
    local latest
    latest=$(awk -F, -v day="$(date +%F)" '
        $1 ~ "^"day { seen[$2] = $0 }
        END { for (k in seen) print seen[k] }
    ' "$METRICS_LOG" 2>/dev/null | sort)

    mkdir -p "$(dirname "$out")"
    {
        cat <<HTML
<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Server report - $host - $(date +%F)</title>
<style>
  body{font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;
       background:#0f172a;color:#e2e8f0;margin:0;padding:2rem}
  h1{font-size:1.4rem;margin:0 0 .2rem}
  .sub{color:#94a3b8;font-size:.85rem;margin-bottom:1.5rem}
  .cards{display:flex;flex-wrap:wrap;gap:1rem;margin-bottom:1.5rem}
  .card{background:#1e293b;border-radius:12px;padding:1rem 1.25rem;min-width:150px}
  .card .k{font-size:.75rem;color:#94a3b8;text-transform:uppercase;letter-spacing:.05em}
  .card .v{font-size:1.5rem;font-weight:700;margin-top:.25rem}
  table{width:100%;border-collapse:collapse;background:#1e293b;border-radius:12px;overflow:hidden}
  th,td{padding:.6rem .9rem;text-align:left;font-size:.9rem}
  th{background:#334155;color:#cbd5e1;font-size:.75rem;text-transform:uppercase;letter-spacing:.05em}
  tr+tr td{border-top:1px solid #334155}
  .pill{padding:.15rem .6rem;border-radius:999px;font-size:.75rem;font-weight:700}
  .OK{background:#14532d;color:#86efac}.WARN{background:#713f12;color:#fde047}
  .CRIT{background:#7f1d1d;color:#fca5a5}.UNKNOWN{background:#3f3f46;color:#d4d4d8}
  h2{font-size:1rem;margin:1.5rem 0 .5rem}
  pre{background:#1e293b;border-radius:12px;padding:1rem;overflow:auto;font-size:.85rem}
</style></head><body>
<h1>Daily server report</h1>
<div class="sub">Host: $host &middot; Generated: $now</div>
HTML

        # Summary cards
        local ok warn crit unk
        ok=$(  echo "$latest" | awk -F, '$4=="OK"'      | wc -l)
        warn=$(echo "$latest" | awk -F, '$4=="WARN"'    | wc -l)
        crit=$(echo "$latest" | awk -F, '$4=="CRIT"'    | wc -l)
        unk=$(  echo "$latest" | awk -F, '$4=="UNKNOWN"'| wc -l)
        cat <<HTML
<div class="cards">
  <div class="card"><div class="k">Checks OK</div><div class="v">$ok</div></div>
  <div class="card"><div class="k">Warnings</div><div class="v">$warn</div></div>
  <div class="card"><div class="k">Critical</div><div class="v">$crit</div></div>
  <div class="card"><div class="k">Unknown</div><div class="v">$unk</div></div>
</div>
HTML

        echo '<h2>Latest check results</h2>'
        echo '<table><tr><th>Metric</th><th>Value</th><th>Status</th><th>Detail</th></tr>'
        if [ -n "$latest" ]; then
            echo "$latest" | while IFS=, read -r ts metric value st msg; do
                printf '<tr><td>%s</td><td>%s</td><td><span class="pill %s">%s</span></td><td>%s</td></tr>\n' \
                    "$(echo "$metric" | html_escape)" "$(echo "$value" | html_escape)" \
                    "$st" "$st" "$(echo "$msg" | html_escape)"
            done
        else
            echo '<tr><td colspan="4">No metrics recorded today yet.</td></tr>'
        fi
        echo '</table>'

        echo '<h2>Top processes by CPU</h2>'
        echo '<pre>'
        top_processes | html_escape
        echo '</pre>'

        echo '<h2>Uptime &amp; load</h2>'
        echo '<pre>'
        uptime | html_escape
        echo '</pre>'

        echo '</body></html>'
    } > "$out"
    log_line "INFO" "REPORT" "wrote $out"
}
