#!/bin/bash
# Build App Dashboard, install to /Applications, and relaunch.
# Run after editing Sources/Config.swift to add or change apps.
set -eo pipefail
cd "$(dirname "$0")"

# Regenerate the project so any newly added Sources/*.swift files are included.
echo "Generating project…"
xcodegen generate >/dev/null

echo "Building…"
xcodebuild -project AppDashboard.xcodeproj -scheme AppDashboard \
  -configuration Debug -derivedDataPath ./build build

echo "Reinstalling…"
pkill -f "App Dashboard.app" 2>/dev/null || true
sleep 1
rm -rf "/Applications/App Dashboard.app"
cp -R "build/Build/Products/Debug/App Dashboard.app" "/Applications/App Dashboard.app"

echo "Launching…"
open "/Applications/App Dashboard.app"
echo "Done — check the menu bar."
