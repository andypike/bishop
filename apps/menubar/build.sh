#!/usr/bin/env bash
# Builds "Agent Status.app" into apps/menubar/build/.
# Needs Xcode or the Xcode command line tools (Swift 5.9+), macOS 13+.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
bin=$(swift build -c release --show-bin-path)

app="build/Agent Status.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$bin/AgentStatus" "$app/Contents/MacOS/"
cp Info.plist "$app/Contents/"
codesign --force --sign - "$app"

echo "Built $PWD/$app"
echo "Copy it to /Applications and open it from there (Open at login needs a fixed location)."
