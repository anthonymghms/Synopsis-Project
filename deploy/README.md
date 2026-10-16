# Paragospels VPS deployment

Target: Ubuntu 24.04 / Python 3.12 on the Vultr VPS `144.202.29.152`.
Nginx serves the Flutter build and forwards `/api/` to one Gunicorn worker on
`127.0.0.1:8010`. Firebase remains the external database, authentication service,
and object store. Build Flutter on the development Mac, not this 1 GB VPS.

## Files and layout

| Path on VPS | Purpose / ownership |
| --- | --- |
| `/opt/paragospels/releases/<release>/` | Backend source, root-owned, readable by the app user |
| `/opt/paragospels/current` | Symlink to the active backend release |
| `/opt/paragospels/venv` | Python virtual environment, root-owned |
| `/var/www/paragospels` | Only the contents of the Flutter `build/web` directory |
| `/etc/paragospels/app.env` | Environment file: `root:root`, mode `0600` |
| `/etc/paragospels/firebase-service-account.json` | Credential: `root:paragospels`, mode `0640` |
| `/run/paragospels` | Temporary Gunicorn files, created by systemd |
| `/var/lib/paragospels` | App home/state directory, created by systemd |

The service account `paragospels` is a dedicated system user with `/usr/sbin/nologin`;
it is not the SSH administrator (`linuxuser`). Make `/etc/paragospels` owned by
`root:paragospels` with mode `0750`. Keep the source and virtual environment
unwritable by the app user. Never put the Firebase private key in a release,
Flutter assets, the webroot, or Git.

## Manual installation

For the first backend installation on the VPS already prepared for this project,
commit and push `deploy/` with the application, then pull it into the VPS checkout
and run this as `linuxuser`:

```bash
bash deploy/install-backend.sh
```

The script exports the committed backend into a root-owned release under
`/opt/paragospels/releases`, installs its dependencies, and enables the systemd
service. It checks that an unauthenticated local API request returns the expected
401 response. This does not test live Firebase access. It refuses to replace an
existing installation, so it cannot interrupt an existing import. It does not
deploy the frontend, edit Firebase rules, change DNS, or configure HTTPS.
If installation stops with an error, inspect it before attempting further steps.

After initial OS updates and SSH/firewall setup, install `python3-venv` and
`nginx`. Allow SSH before enabling a firewall; expose HTTP/HTTPS, but keep port
8010 private. The steps below are an operator checklist, not an unattended script.

1. Create the service user and directories described above. Upload a reviewed
   backend release containing the root Python modules, `services/`, `localization/`,
   `requirements.txt`, and `deploy/`. Point `/opt/paragospels/current` to it.
   Do not upload the whole development checkout or its `venv`, credentials,
   caches, test fixtures, or generated mobile files.
2. Create `/opt/paragospels/venv` with `python3 -m venv`. Install dependencies:

   ```bash
   sudo /opt/paragospels/venv/bin/python -m pip install -r /opt/paragospels/current/deploy/requirements.txt
   sudo /opt/paragospels/venv/bin/python -m pip check
   ```

3. Securely install the Firebase credential at the path above. Copy
   `app.env.example` to `/etc/paragospels/app.env`, review the bucket and allowed
   origins, and apply the permissions in the table. `FIREBASE_SERVICE_ACCOUNT`
   is the setting used by this application's Firebase initializer.
4. Copy `paragospels.service` to `/etc/systemd/system/paragospels.service`:

   ```bash
   sudo systemd-analyze verify /etc/systemd/system/paragospels.service
   sudo systemctl daemon-reload
   sudo systemctl enable --now paragospels.service
   sudo systemctl status paragospels.service --no-pager
   ```

5. Build the web frontend from `gospel_frontend` on the Mac:

   ```bash
   flutter build web --release --dart-define=API_BASE_URL=/api --pwa-strategy=none
   ```

   This relative API URL supports initial IP-based checks and the final domain.
   Do not reuse this relative value for native mobile builds; those should use
   `https://paragospels.com/api`. Disable Flutter's generated offline service
   worker for this deployment so an earlier cached application does not mask a
   new release. Flutter 3.47.2 accepts `--pwa-strategy=none` as a hidden,
   deprecated option; recheck when upgrading Flutter.
6. Copy **only the contents** of `gospel_frontend/build/web/` into
   `/var/www/paragospels/`, with directories readable/traversable and files
   readable by Nginx (`0755` directories, `0644` files). Preserve the previous
   build outside the webroot for rollback. Publish builds as a complete unit.
7. Install `nginx-paragospels.conf` as
   `/etc/nginx/sites-available/paragospels`, symlink it in `sites-enabled`, and
   remove the default site symlink on this fresh server. Validate before reload:

   ```bash
   sudo nginx -t
   sudo systemctl reload nginx
   ```

## Verification and domain cutover

Before changing GoDaddy DNS, check static delivery and API routing on the new
server. These requests do not write application data:

```bash
curl -I http://144.202.29.152/
curl -I http://144.202.29.152/main.dart.js
curl -i http://144.202.29.152/api/topics
curl -I http://144.202.29.152/serviceAccountKey.json
```

Expected: HTML and JavaScript return `200` with `Cache-Control: no-cache`;
the unauthenticated API returns its JSON authentication error (normally `401`,
not Nginx `502` or SPA HTML); the credential filename returns `404`.
Check `sudo ss -lntp` to ensure port 8010 listens only on `127.0.0.1`.
The API must start and connect to Firebase successfully before cutover.

Point the domain's website DNS records to the new VPS, then issue an HTTPS
certificate for `paragospels.com` and `www.paragospels.com` using the installed
ACME client. Configure HTTP-to-HTTPS redirect after issuance and, if desired,
redirect `www` to the apex. Keep the certificate renewal timer enabled and test
renewal. Add the final domain(s) to Firebase Authentication's authorized domains.
Use HTTPS for sign-in and authenticated application testing. The supplied Nginx
file is the initial HTTP configuration; it intentionally contains no invented
certificate paths or certificate that has not yet been issued.

Validate login, reader access, and authorized admin behavior in the browser
after HTTPS is active. Check memory and disk use before a controlled import.

## Operations and limits

- Run only one import at a time on this 1 GB VPS. The application's executor
  currently permits two; the deployment configuration does not change that.
  A strict concurrency guard requires a separate application change.
- Background imports run inside the API process and do not survive a restart.
  Wait for imports to finish before deploying, restarting, or rebooting. A long
  graceful shutdown timeout is not a durable queue or a recovery guarantee.
- There is one Gunicorn worker with four request threads, no preload, and no
  automatic request-count recycling. More workers would duplicate memory and
  the in-process import executor. Review measurements before increasing them.
- API responses are marked `no-store` at Nginx because they depend on user
  authentication. Flutter files revalidate instead of using long immutable
  caching for filenames reused between builds.
- Read logs using `sudo journalctl -u paragospels.service -n 100 --no-pager` and
  the normal Nginx logs. Monitor memory, free disk, service health, and backup
  success; test restore. Vultr image backups do not back up external Firestore
  or Firebase Storage data.
- For rollback, select the previous backend release and matching frontend
  build, confirm compatible dependency versions, and restart only after imports
  finish. A code rollback does not reverse Firebase data changes.

Gunicorn uses the [official 26.2.2 release](https://github.com/benoitc/gunicorn/releases/tag/26.2.2),
pinned to its immutable commit and SHA-256-verified source archive. Direct PyPI
checks on 2026-10-16 exposed only 26.2.0, while 26.2.1 includes HTTP framing and
resource-exhaustion fixes. The patched archive was successfully built and
installed locally; its Python requirement is `>=3.10`, including Python 3.12.
Nginx buffers/reframes requests and Gunicorn stays private, but the patch avoids
relying solely on those mitigations. Review and test future dependency updates.
