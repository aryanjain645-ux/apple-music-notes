#!/bin/bash
# Build SongNotes.app and install it to ~/Applications.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP=build/SongNotes.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/SongNotes "$APP/Contents/MacOS/SongNotes"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - --identifier com.songnotes.app "$APP"

mkdir -p "$HOME/Applications"
pkill -x SongNotes 2>/dev/null || true
rm -rf "$HOME/Applications/SongNotes.app"
cp -R "$APP" "$HOME/Applications/"
echo "Installed: $HOME/Applications/SongNotes.app"
echo "Launch:    open ~/Applications/SongNotes.app"
