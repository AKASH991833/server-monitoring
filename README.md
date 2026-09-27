# server-monitoring

A small, dependency-free Linux monitoring toolkit written in Bash: it checks
**CPU, load, memory, disk, inodes and systemd services**, logs every result,
sends **email / Telegram alerts** when thresholds are crossed, and renders a
**daily HTML report**. Scheduled with **cron or a systemd timer**.

Built as a learning + portfolio project for Linux system administration.
Everything is plain Bash + standard tools (`/proc`, `df`, `ps`, `systemctl`,
`curl`) - no agents, no databases, nothing to compile.

## Features

- CPU usage, load-per-core, memory, disk space, inode usage, service status
- Per-metric WARN / CRIT thresholds in one config file
- Alerts by email (local MTA) and/or Telegram bot, with per-alert cooldown so
  a flapping disk doesn't spam you
- Append-only metrics log (`metrics.csv`) + event log (`events.log`)
- Self-contained daily HTML report (inline CSS, no JS)
- One-command install for a single user or system-wide, cron **or** systemd timer
- Dry-run install, smoke tests, zero external dependencies

## Quick start

```bash
git clone https://github.com/AKASH991833/server-monitoring.git
cd server-monitoring

# try it right away, no install needed
./monitor.sh --test          # --test prints alerts instead of sending them

# install for your user (no sudo) with cron scheduling
./install.sh

# or system-wide with a systemd timer
sudo ./install.sh --system --method systemd
```

After installing:

1. Edit thresholds in `~/.config/server-monitoring/monitor.conf`
   (or `/etc/server-monitoring/monitor.conf` for `--system`).
2. Copy real alert credentials into `secrets.env` next to it
   (see `config/secrets.example.env`). `secrets.env` is git-ignored on purpose.
3. `./run.sh --test` to verify, `./run.sh --report` for the HTML report.

Default schedule (added by `install.sh`):

```cron
*/5 * * * * <prefix>/run.sh --quiet          # checks every 5 minutes
55 23 * * * <prefix>/run.sh --quiet --report # daily report at 23:55
```

## How it works (the interview version)

```
monitor.sh ── sources ──> config/monitor.conf  (thresholds, services, channels)
   │                      config/secrets.env   (credentials, never committed)
   │
   ├─> lib/checks.sh    one function per metric, prints TSV: name/value/status/message
   │      cpu      → diff /proc/stat twice 1s apart: 1 - Δidle/Δtotal
   │      load     → /proc/loadavg 1-min ÷ online cores
   │      memory   → (MemTotal - MemAvailable) / MemTotal  from /proc/meminfo
   │      disk     → df -P, skipping tmpfs/devtmpfs/squashfs/overlay
   │      inodes   → df -Pi (free space ≠ free inodes)
   │      services → systemctl is-active per configured unit
   │
   ├─> appends to logs/metrics.csv + logs/events.log
   │
   ├─> lib/alerts.sh    WARN/CRIT → cooldown check → email and/or Telegram
   │      cooldown = one state file per metric; mtime compared against
   │      ALERT_COOLDOWN_MIN, so repeats stay silent for 30 min
   │
   └─> lib/report.sh    latest value per metric → styled HTML report
```

Questions this answers in an interview:

- **"How do you measure CPU usage in Bash?"** Read the first `cpu` line of
  `/proc/stat` twice with a gap; the counters are cumulative jiffies per state,
  so usage = `(Δtotal − Δidle) / Δtotal`. A single read can't give you a rate.
- **"Why MemAvailable and not free memory?"** Linux uses idle RAM for page
  cache; `free` understates what applications can still get. `MemAvailable`
  (kernel ≥ 3.14) is the kernel's own estimate of usable memory.
- **"How do you avoid alert spam?"** Cooldown state per metric; the alert is
  only re-sent after `ALERT_COOLDOWN_MIN` minutes.
- **"Cron vs systemd timer?"** Cron is everywhere and simple. A systemd timer
  adds `OnBootSec` catch-up, dependencies (`After=network-online.target`),
  journald logging and `systemctl list-timers` visibility. This project ships
  both - pick per machine.
- **"Why check inodes?"** Millions of tiny files can exhaust the inode table
  while `df -h` still shows free space; `touch` then fails with
  "No space left on device". `df -i` catches that.

## Configuration

Everything lives in `config/monitor.conf` - threshold values, the service
list, alert channels, cooldown, log paths. The installed copy is rewritten by
`install.sh` to point at absolute log/state dirs; your edits are never
overwritten on reinstall.

## Alerts

- **Email**: uses the local `mail` command, so the box needs an MTA
  (`postfix`, `ssmtp`, ...) or set `ALERT_EMAIL=no`.
- **Telegram**: create a bot with @BotFather, message it once, get your chat
  id from `getUpdates`, and put both values in `secrets.env`.
  The script then POSTs to the Bot API with `curl`.

Both channels print instead of sending when you run `./monitor.sh --test`,
which is what the smoke tests use.

## Project layout

```
server-monitoring/
├── monitor.sh               # entry point (checks, logging, alerting, report)
├── lib/
│   ├── checks.sh            # metric collectors (read-only, no side effects)
│   ├── alerts.sh            # email + Telegram senders, cooldown bookkeeping
│   └── report.sh            # HTML report renderer
├── config/
│   ├── monitor.conf         # thresholds, services, channels, paths
│   └── secrets.example.env  # credential template (copy → secrets.env)
├── install.sh               # user/system install, cron or systemd
├── uninstall.sh             # removes scheduled jobs
├── systemd/                 # .service + .timer templates
├── cron/server-monitoring.cron  # reference crontab
├── tests/test_monitor.sh    # 18 smoke tests (bash tests/test_monitor.sh)
└── docs/sample-report.html  # real report generated on Linux
```

## Testing

```bash
bash tests/test_monitor.sh
```

Covers: syntax of every script, a forced-WARN run, CSV/event log output,
TEST_MODE alert output, cooldown suppression of repeats, HTML report
contents, and a dry-run install. Last run: **17 passed, 0 failed** on Linux.

See `docs/sample-report.html` for a real generated report.

## Roadmap

- Network connectivity + open-port checks (`ss`, ping gateway)
- Certificate expiry checks for HTTPS endpoints
- Prometheus-style text export (`node_exporter` format)
- Slack / webhook alert channel
- Debian/RPM packaging

## License

MIT - see [LICENSE](LICENSE).
