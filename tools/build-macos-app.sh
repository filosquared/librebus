#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
PYTHON_BIN="${PYTHON_BIN:-python3}"

if ! "$PYTHON_BIN" -c 'import PyInstaller' >/dev/null 2>&1; then
	echo "PyInstaller is missing. Install requirements-macos.txt first." >&2
	exit 1
fi

"$PYTHON_BIN" -m PyInstaller \
	--noconfirm \
	--clean \
	--windowed \
	--name LibreCap \
	--osx-bundle-identifier com.filosquared.librecap \
	--paths "$ROOT_DIR" \
	--add-data "$ROOT_DIR/html:html" \
	--add-data "$ROOT_DIR/static:static" \
	--collect-all webview \
	--distpath "$ROOT_DIR/dist" \
	--workpath "$ROOT_DIR/build/macos" \
	--specpath "$ROOT_DIR/build/macos" \
	"$ROOT_DIR/macos_app.py"

echo "Built $ROOT_DIR/dist/LibreCap.app"
