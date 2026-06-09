#!/bin/bash
# Builds Earwig and packages it as Earwig.app (required so macOS can grant
# microphone / system-audio / speech-recognition permissions to the app).
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
swift build -c "$CONFIG"

BIN=".build/$CONFIG/Earwig"
APP="Earwig.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Earwig"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Earwig</string>
    <key>CFBundleIdentifier</key><string>io.darkin.earwig</string>
    <key>CFBundleName</key><string>Earwig</string>
    <key>CFBundleDisplayName</key><string>Earwig</string>
    <key>CFBundleVersion</key><string>0.1.0</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSUIElement</key><true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Earwig records your side of meetings so it can transcribe them.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>Earwig transcribes recorded meetings on-device.</string>
    <key>NSAudioCaptureUsageDescription</key>
    <string>Earwig records meeting audio (the other participants) so it can transcribe the conversation.</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $APP"
