# Librebus

<img src="screenshots/librusik.png" alt="Librebus preview" width="600"/>

Librebus is a self-hosted, open-source school journal for students and families. It provides a lightweight web interface for grades, attendance, timetable, homework, school days off, messages, and account settings.

The included Librus/Synergia adapter is optional and uses credentials supplied by the account owner. Librebus is an independent community project; it is not affiliated with Librus. Do not expose an instance publicly without TLS, a trusted reverse proxy, and appropriate access controls.

## Features

- Grades with independent average calculation
- Messages and attachment downloads
- Attendance summaries and per-semester views
- Timetable, homework, school free days, and teacher free days
- HttpOnly server-managed sessions
- Dark theme and optional confetti
- Administrator panel with registration, account, and tier controls
- SQLite persistence with migration from older JSON installations

## Installation

```bash
git clone https://github.com/filosquared/librebus.git
cd librebus
python3 -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt
python3 librusik.py --skip-wizard
```

On first start, Librebus creates its data directory and prints a randomly generated administrator password. Open [http://localhost:7777](http://localhost:7777), visit `/panel`, sign in, and change that password immediately. New installations listen on `127.0.0.1`; set `LIBREBUS_LISTEN_ADDRESS=0.0.0.0` only when the service is intentionally being exposed through a protected network boundary.

The interactive setup wizard can be used by omitting `--skip-wizard` on the first run.

## macOS app

The macOS wrapper bundles the server and opens the interface in one native window. It stores application data in `~/Library/Application Support/Librebus`.

For development:

```bash
pip install -r requirements-macos.txt
python3 macos_app.py
```

To build a double-clickable `.app`:

```bash
pip install -r requirements-macos.txt
./tools/build-macos-app.sh
open dist/Librebus.app
```

The first app launch shows the generated administrator password in a macOS dialog. Save it and change it from the panel.

## iOS client

The repository includes a native SwiftUI iOS app in `ios/`. It connects directly to Librus, stores credentials in the iPhone Keychain, and caches synchronized school data on-device. It does not require a Librebus server. See [`ios/README.md`](ios/README.md) for the Xcode setup.

A signed iOS build requires the full Xcode application and Apple signing configuration.

## Configuration and data

Runtime state is stored in `data/`:

- `librebus.sqlite3` contains configuration and application accounts.
- `fernet.key` encrypts stored upstream credentials and must be protected.
- `profile_pics/` contains uploaded profile images.

If `config.json` or `database.json` exists, it is migrated once into SQLite and retained as a recoverable backup. Never commit `data/`, real student information, passwords, session tokens, or provider API responses.

Environment overrides:

```bash
LIBREBUS_DATA_DIR=/srv/librebus/data
LIBREBUS_LISTEN_ADDRESS=127.0.0.1
LIBREBUS_PORT=7777
```

Registration is disabled by default. Enable it from the administrator panel only when the instance is ready to accept new users.

## Docker

```bash
docker build -t librebus .
docker run -d --name librebus \
  -p 7777:7777 \
  -v "$(pwd)/data:/app/data" \
  librebus
```

The container listens on all interfaces inside the container and persists state through `/app/data`. Put TLS and authentication at a reverse proxy when running it outside a trusted local network.

## Development checks

```bash
PYTHONPYCACHEPREFIX=/tmp/librebus-pycache python3 -m compileall -q .
python3 -m unittest discover -s tests
git diff --check
```

Tests are offline and use synthetic data. Do not add live Librus credentials or real student records to the repository.

## License

Librebus is distributed under the MIT License. See [LICENSE](LICENSE).
