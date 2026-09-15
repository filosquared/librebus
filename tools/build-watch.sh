#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-Debug}"
DESTINATION="${DESTINATION:-generic/platform=watchOS Simulator}"

xcodebuild \
    -project "$ROOT_DIR/ios/LibreCap.xcodeproj" \
    -scheme LibreCapWatch \
    -configuration "$CONFIGURATION" \
    -destination "$DESTINATION" \
    -derivedDataPath "$ROOT_DIR/build/watch" \
    build
