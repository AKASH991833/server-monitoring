# First time using Linux? Start here

This guide starts with zero assumptions. You can try the monitor without installing it, sending alerts, or changing system settings. These commands run in a **terminal**: a window where you type commands and press Enter. Use an Ubuntu/Debian Linux machine, Linux VM or WSL. Other Linux distributions can work, but installation commands vary.

## 1. What does this project do?

A server is a computer that provides something to other computers. A monitor checks whether it is running out of resources or whether a service stopped.

```text
Your Linux computer
       │
       ├── monitor.sh reads CPU, RAM, disks and services
       │        └── saves measurements to logs/metrics.csv
       ├── thresholds in config/monitor.conf say when to warn
       ├── optional alerts notify you (OFF by default)
       └── dashboard/app.py reads the saved CSV and draws charts
```

| Word | Simple meaning | Example |
| --- | --- | --- |
| CPU | The computer's working capacity | 90% usage means it is busy |
| RAM / memory | Short-term working space | 90% usage leaves little room for apps |
| Disk | Long-term file storage | 90% full means uploads may fail |
| Inode | A slot for tracking one file | Millions of tiny files can use them up |
| Service | A program meant to keep running | `nginx` serves websites |
| WARN / CRIT | Look soon / take action now | Defaults: disk WARN 80%, CRIT 90% |
| CSV | A plain text table of measurements | Can open in a spreadsheet |
| localhost | This machine itself, not a public website | `127.0.0.1` |

## 2. Get the code

Open Terminal. First check you have Git and Python:

```bash
git --version
python3 --version
```

If either says "command not found" on Ubuntu/Debian, run `sudo apt update && sudo apt install git python3`. `sudo` asks for **your own Linux password**, not one from this project. On other distributions, use your package manager.

```bash
git clone https://github.com/AKASH991833/server-monitoring.git
cd server-monitoring
```

`cd` means change directory. If you already cloned it, use `cd server-monitoring && git pull` instead. Run `pwd` to see your current folder; run `ls` to list the files.

## 3. Safe first run

```bash
./monitor.sh --test
```

This reads *your current Linux machine*, prints each result, and saves data in `logs/metrics.csv`. `--test` prevents real email/Telegram sends. `OK` means below warning threshold; `WARN` means above the first threshold; `CRIT` means above the second; `UNKNOWN` means it couldn't check. A warning or critical exit status can be normal for a busy machine. If services say UNKNOWN in WSL or a container, systemd may not be running. No need to use `sudo` for the first run.

If the command says "Permission denied", use `bash monitor.sh --test`. If `git clone` fails, check internet access and the repository URL. If you get a shell error after editing config, restore it with `git checkout -- config/monitor.conf` (this discards changes to that file only).

## 4. Set your own thresholds with a wizard

```bash
python3 setup.py
```

Press Enter to accept a suggested number, or type a whole number. WARN must be lower than CRIT. Enter systemd service names separated by spaces (`ssh nginx cron`) or keep the default. You can leave alerts off. The wizard shows a summary and asks before saving. It modifies **config/monitor.conf**, never reads or asks for passwords. To configure an installed copy instead, run `python3 setup.py --config ~/.config/server-monitoring/monitor.conf` after installation. On a system-wide installation, the config is `/etc/server-monitoring/monitor.conf`; use appropriate permissions.

Run another `./monitor.sh --test` to see the effect. The normal checks use CPU /proc counters, the kernel's available-memory estimate, and `df` for disks. Service checks use `systemctl` when available.

## 5. See your measurements as graphs

Run the monitor a few times, about a minute apart, to get more than one graph point. Then open a second terminal in the repo folder:

```bash
python3 dashboard/app.py
```

Open **http://127.0.0.1:8765/** in a browser on the **same machine**. CPU, load, memory, disk and inode charts show the recent measurements. The table explains the latest check state. The page refreshes every 60 seconds, but *the dashboard does not itself collect new data*. Run `./monitor.sh --test` again in the first terminal for a new point. Press Ctrl+C in the second terminal to stop the web server.

The default dashboard listens only on `127.0.0.1`, not your network. It has **no login or TLS**. Do not bind it to `0.0.0.0`, port-forward it, or put it directly on the public internet. On a remote server, use SSH tunneling instead: `ssh -L 8765:127.0.0.1:8765 user@server` and visit localhost on your own computer. If the browser says it cannot connect, check that Python is still running and the port isn't occupied. For an installed copy, use `python3 dashboard/app.py --metrics ~/.local/state/server-monitoring/logs/metrics.csv` (system-wide: `/var/log/server-monitoring/metrics.csv`, subject to read permissions).

## 6. Automate checks only when ready

`./install.sh --dry-run` previews what installation would do. `./install.sh` copies files into your home directory and attempts to schedule cron checks every five minutes. Use `./install.sh --method systemd` if user systemd is available. The first run doesn't require installation. Installation changes your crontab or user timer; check what it does before enabling it. Run `./uninstall.sh` to remove its schedule (see script for options).

Email needs a working local `mail` command; Telegram needs bot credentials and `curl`. Both are **off by default**. Put real values only in `secrets.env` beside the active config, set `chmod 600` on that file, and never commit it. See [README](../README.md#alerts). The dashboard needs neither alert channel.

## Troubleshooting and learning path

- Empty dashboard? Run the monitor first and make sure the `--metrics` path matches the actual CSV. `ls -l logs/metrics.csv` checks it.
- One point makes a flat graph. Run again later. Stale-data warning means the CSV has not gained a new measurement in 15 minutes.
- Disk missing? A container may have only overlay filesystems, excluded by default; use `DISK_MOUNTS="/"` in the config if you want to check `/` explicitly.
- Inodes and disks are distinct. To see raw values, type `df -h` and `df -i`.
- To inspect collector code, read `lib/checks.sh`; alerts in `lib/alerts.sh`; report in `lib/report.sh`; dashboard in `dashboard/app.py`. Each part has one job.
- Don't claim this is a production monitoring replacement. It is a learning project with local CSV data and no centralized storage or authenticated dashboard. In an interview, explain that difference honestly.
