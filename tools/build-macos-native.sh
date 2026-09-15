#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build/macos-native"
OUTPUT_DIR="$ROOT_DIR/dist/native"

# Local ad-hoc signing: no paid developer account or Python runtime required.
xcodebuild \
    -project "$ROOT_DIR/ios/LibreCap.xcodeproj" \
    -scheme LibreCap \
    -configuration Release \
    -sdk macosx \
    -destination 'platform=macOS' \
    -derivedDataPath "$BUILD_DIR" \
    CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
    -quiet build

mkdir -p "$OUTPUT_DIR"
ditto "$BUILD_DIR/Build/Products/Release/LibreCap.app" "$OUTPUT_DIR/LibreCap.app"
codesign --verify --deep --strict "$OUTPUT_DIR/LibreCap.app"
echo "Built $OUTPUT_DIR/LibreCap.app"
