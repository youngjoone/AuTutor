#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
binary_dir="$(swift build -c release --show-bin-path)"
app_dir="$PWD/dist/AuTutor.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary_dir/AuTutor" "$app_dir/Contents/MacOS/AuTutor"
cp Resources/Info.plist "$app_dir/Contents/Info.plist"
codesign --force --sign "${AUTUTOR_SIGNING_IDENTITY:--}" "$app_dir"
printf 'Built: %s\n' "$app_dir"
