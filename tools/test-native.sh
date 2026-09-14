#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK_DIR="$ROOT_DIR/build/native-checks"
mkdir -p "$CHECK_DIR"

swiftc -module-cache-path "$CHECK_DIR/module-cache" \
    "$ROOT_DIR/ios/Librebus/Models.swift" \
    "$ROOT_DIR/ios/Shared/WatchSnapshot.swift" \
    "$ROOT_DIR/ios/Shared/WatchSnapshotBuilder.swift" \
    "$ROOT_DIR/watchOS/LibrebusWatch/WatchSnapshotCache.swift" \
    "$ROOT_DIR/tests/watch_snapshot_checks.swift" \
    -o "$CHECK_DIR/watch-checks"
"$CHECK_DIR/watch-checks"

swiftc -module-cache-path "$CHECK_DIR/module-cache" \
    "$ROOT_DIR/ios/Librebus/Models.swift" \
    "$ROOT_DIR/ios/Librebus/LibrusClient.swift" \
    "$ROOT_DIR/tests/ios_auth_checks.swift" \
    -o "$CHECK_DIR/auth-checks"
"$CHECK_DIR/auth-checks"

swiftc -module-cache-path "$CHECK_DIR/module-cache" \
    "$ROOT_DIR/ios/Librebus/Models.swift" \
    "$ROOT_DIR/ios/Librebus/AppModel.swift" \
    "$ROOT_DIR/tests/app_model_checks.swift" \
    -o "$CHECK_DIR/model-checks"
"$CHECK_DIR/model-checks"

swiftc -module-cache-path "$CHECK_DIR/module-cache" \
    "$ROOT_DIR/ios/Librebus/Models.swift" \
    "$ROOT_DIR/ios/Shared/WatchSnapshot.swift" \
    "$ROOT_DIR/ios/Shared/WatchSnapshotBuilder.swift" \
    "$ROOT_DIR/ios/Shared/LessonReminder.swift" \
    "$ROOT_DIR/watchOS/LibrebusWatch/WatchLessonAlerts.swift" \
    "$ROOT_DIR/tests/lesson_alert_checks.swift" \
    -o "$CHECK_DIR/lesson-alert-checks"
"$CHECK_DIR/lesson-alert-checks"
