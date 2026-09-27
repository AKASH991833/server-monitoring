#!/usr/bin/env python3
"""Interactive, local-only configuration wizard. Does not ask for secrets."""
import argparse
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parent
DEFAULT = ROOT / 'config' / 'monitor.conf'
FIELDS = [
    ('CPU_WARN', 'CPU warning (%)', 80), ('CPU_CRIT', 'CPU critical (%)', 95),
    ('MEM_WARN', 'Memory warning (%)', 80), ('MEM_CRIT', 'Memory critical (%)', 95),
    ('DISK_WARN', 'Disk warning (%)', 80), ('DISK_CRIT', 'Disk critical (%)', 90),
    ('INODE_WARN', 'Inode warning (%)', 80), ('INODE_CRIT', 'Inode critical (%)', 90),
]

def ask(prompt, default):
    answer = input(f'{prompt} [{default}]: ').strip()
    return answer or str(default)

def percentage(prompt, default):
    while True:
        raw = ask(prompt, default)
        if raw.isdigit() and 1 <= int(raw) <= 100:
            return int(raw)
        print('Enter a whole number from 1 to 100.')

def yesno(prompt, default='no'):
    while True:
        raw = ask(prompt + ' (yes/no)', default).lower()
        if raw in ('yes', 'no'):
            return raw
        print('Type yes or no.')

def main():
    parser = argparse.ArgumentParser(description='Guided configuration for server-monitoring')
    parser.add_argument('--config', type=Path, default=DEFAULT, help='Existing config to update')
    args = parser.parse_args()
    path = args.config.expanduser().resolve()
    if not path.is_file():
        parser.error(f'Config not found: {path}. Run ./install.sh first or use the repo default.')
    if path.is_symlink():
        parser.error('Refusing to write through a symlink')
    text = path.read_text()
    print('Server monitoring setup - press Enter to keep suggested values. No passwords are collected.')
    print(f'Configuration: {path}\n')
    values = {}
    for key, label, default in FIELDS:
        current = re.search(r'^' + key + r'=(\d+)$', text, re.M)
        values[key] = percentage(label, int(current.group(1)) if current else default)
    for group in ('CPU', 'MEM', 'DISK', 'INODE'):
        while values[group + '_WARN'] >= values[group + '_CRIT']:
            print(f'{group}: warning must be lower than critical. Try again.')
            values[group + '_WARN'] = percentage(f'{group} warning (%)', values[group + '_WARN'])
            values[group + '_CRIT'] = percentage(f'{group} critical (%)', values[group + '_CRIT'])
    current_services = re.search(r'^SERVICES="([^"]*)"$', text, re.M)
    while True:
        services = ask('systemd services to watch, space-separated (blank input keeps default)', current_services.group(1) if current_services else 'ssh cron')
        if not services or all(re.fullmatch(r'[a-zA-Z0-9_.@-]+', x) for x in services.split()):
            break
        print('Use simple systemd unit names only, e.g. ssh nginx cron.')
    email = yesno('Enable email alerts? Requires local mail command and config/secrets.env')
    telegram = yesno('Enable Telegram alerts? Requires curl and config/secrets.env')
    for key, val in {**values, 'SERVICES': f'"{services}"', 'ALERT_EMAIL': email, 'ALERT_TELEGRAM': telegram}.items():
        replacement = f'{key}={val}'
        if re.search(r'^' + key + r'=', text, re.M):
            text = re.sub(r'^' + key + r'=.*$', lambda m: replacement, text, count=1, flags=re.M)
        else:
            text += '\n' + replacement + '\n'
    print('\nSummary: ' + ', '.join(f'{k}={v}' for k, v in values.items()))
    print('Services:', services or '(none)', '| email:', email, '| Telegram:', telegram)
    if yesno('Save this config?', 'yes') != 'yes':
        print('No changes saved.'); return
    import os, tempfile
    fd, tmp = tempfile.mkstemp(prefix='.monitor-', dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as f:
            f.write(text)
        os.chmod(tmp, path.stat().st_mode & 0o777)
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp): os.unlink(tmp)
    print(f'Saved {path}. Run ./monitor.sh --test --config {path} to try it.')
    if email == 'yes' or telegram == 'yes':
        print('Put alert details in secrets.env next to the config, chmod 600; never commit credentials.')

if __name__ == '__main__':
    try: main()
    except (KeyboardInterrupt, EOFError):
        print('\nCancelled; no changes saved.', file=sys.stderr); sys.exit(1)
