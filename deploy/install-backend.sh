#!/usr/bin/env bash
# First installation on the prepared Ubuntu VPS; run as the SSH administrator.
set -Eeuo pipefail
umask 022

fail() { printf '%s\n' "$*" >&2; exit 1; }

[[ $(uname -s) == Linux ]] || fail 'Run this script on the Ubuntu VPS, not the Mac.'
[[ $EUID -ne 0 ]] || fail 'Run: bash deploy/install-backend.sh (without sudo).'

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd -- "$repo_dir"
command -v git >/dev/null || fail 'Git is required.'
command -v python3 >/dev/null || fail 'Python 3 is required.'
sudo -v

# Stop rather than restarting an existing app: imports live inside its process.
if sudo systemctl is-active --quiet paragospels.service ||
   sudo test -e /etc/systemd/system/paragospels.service ||
   sudo test -e /opt/paragospels/current ||
   sudo test -L /opt/paragospels/current; then
    fail 'An installation already exists. This script is for the first installation only; do not restart an app while an import is running.'
fi

id paragospels >/dev/null 2>&1 || fail 'The prepared paragospels service user is missing.'
sudo test -x /opt/paragospels/venv/bin/python || fail 'The prepared Python environment is missing.'
sudo -u paragospels test -r /etc/paragospels/firebase-service-account.json ||
    fail 'The paragospels user cannot read its protected Firebase credential.'

# Export only committed backend files; keep the SSH checkout and web files apart.
paths=(
    app.py admin_api.py admin_content_api.py admin_users_api.py user_activity_api.py
    services localization/interface_translations.json requirements.txt
    deploy/requirements.txt deploy/gunicorn.conf.py
    deploy/paragospels.service deploy/app.env.example
)
for path in "${paths[@]}"; do
    git cat-file -e "HEAD:$path" || fail "Commit and push the missing file first: $path"
done
git diff --quiet HEAD -- "${paths[@]}" || fail 'The backend has uncommitted changes. Commit and push them before installing.'

release=$(git rev-parse --short=12 HEAD)
release_dir="/opt/paragospels/releases/$release"
sudo install -d -o root -g root -m 0755 /opt/paragospels/releases "$release_dir"
git archive --format=tar HEAD "${paths[@]}" |
    sudo tar --no-same-owner -xf - -C "$release_dir"

sudo /opt/paragospels/venv/bin/python -m pip install -r "$release_dir/deploy/requirements.txt"
sudo /opt/paragospels/venv/bin/python -m pip check

sudo install -d -o root -g paragospels -m 0750 /etc/paragospels
if ! sudo test -e /etc/paragospels/app.env; then
    sudo install -o root -g root -m 0600 "$release_dir/deploy/app.env.example" /etc/paragospels/app.env
fi
sudo ln -s "$release_dir" /opt/paragospels/current
sudo systemd-analyze verify "$release_dir/deploy/paragospels.service"
sudo install -o root -g root -m 0644 "$release_dir/deploy/paragospels.service" /etc/systemd/system/paragospels.service
sudo systemctl daemon-reload
sudo systemctl enable --now paragospels.service

# A request without a token must reach Flask and be rejected without reading or
# changing account data. This does not validate live Firebase permissions.
python3 - <<'PY'
import json
import time
from urllib.error import HTTPError, URLError
from urllib.request import ProxyHandler, build_opener

opener = build_opener(ProxyHandler({}))
deadline = time.monotonic() + 30
while time.monotonic() < deadline:
    try:
        with opener.open('http://127.0.0.1:8010/topics', timeout=3) as response:
            raise SystemExit(f'Unexpected unauthenticated response: HTTP {response.status}. Inspect the service before continuing.')
    except HTTPError as error:
        try:
            payload = json.loads(error.read())
        except (ValueError, UnicodeDecodeError):
            payload = {}
        if error.code == 401 and isinstance(payload, dict) and payload.get('error', {}).get('code') == 'authentication_required':
            print('Backend check passed: HTTP 401 authentication_required (expected without login).')
            break
        raise SystemExit(f'Unexpected backend response: HTTP {error.code}. Inspect the service before continuing.')
    except (URLError, TimeoutError):
        time.sleep(1)
else:
    raise SystemExit('Backend did not become ready. Run: sudo journalctl -u paragospels -n 40 --no-pager')
PY

sudo systemctl is-active paragospels.service
sudo systemctl is-enabled paragospels.service
printf 'Backend installed from commit %s. It listens on 127.0.0.1:8010.\n' "$release"
printf '%s\n' 'Website build, Firebase launch checks, domain connection, and HTTPS are the next steps.'
