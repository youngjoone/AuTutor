#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# XCTest ships with full Xcode, not the standalone Command Line Tools.
# Only this process changes developer directory; system settings are untouched.
if [[ -z "${DEVELOPER_DIR:-}" ]] && [[ "$(xcode-select -p)" == /Library/Developer/CommandLineTools ]] && [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
xcrun swift test "$@"
