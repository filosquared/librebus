#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
ANDROID_DIR="$ROOT_DIR/android"

if [ ! -f "$ANDROID_DIR/local.properties" ] && [ -z "${ANDROID_HOME-}" ] && [ -z "${ANDROID_SDK_ROOT-}" ]; then
    echo "Set ANDROID_HOME/ANDROID_SDK_ROOT or create android/local.properties first." >&2
    exit 1
fi

"$ANDROID_DIR/gradlew" -p "$ANDROID_DIR" :app:assembleRelease --console=plain
echo "Built $ANDROID_DIR/app/build/outputs/apk/release/app-release-unsigned.apk"
