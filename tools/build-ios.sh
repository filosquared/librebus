#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/ios/LibreCap.xcodeproj"
CONFIGURATION="${CONFIGURATION:-Debug}"
DESTINATION="${DESTINATION:-generic/platform=iOS Simulator}"

if ! xcodebuild -version >/dev/null 2>&1; then
	cat >&2 <<'MESSAGE'
Full Xcode is required to build LibreCap for iOS.
Install Xcode from the Mac App Store, open it once, and accept its license.
MESSAGE
	exit 1
fi

xcodebuild \
	-project "$PROJECT_PATH" \
	-scheme LibreCap \
	-configuration "$CONFIGURATION" \
	-destination "$DESTINATION" \
	-derivedDataPath "$ROOT_DIR/build/ios" \
	build
