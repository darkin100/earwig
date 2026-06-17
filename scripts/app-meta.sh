#!/bin/bash
# Shared app metadata + Info.plist writer, sourced by build.sh and package.sh.
# MUST be sourced with the repo root as the current directory.

# Version: marketing version from VERSION (bumped by hand); build number is the git commit count
# (auto-increments); plus the short SHA. Resend feedback key is baked in from a gitignored file or
# the EARWIG_RESEND_KEY env var (never committed).
EARWIG_VERSION="$(tr -d '[:space:]' < VERSION 2>/dev/null || echo 0.0.0)"
EARWIG_BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 0)"
EARWIG_SHA="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
EARWIG_RESEND_KEY="${EARWIG_RESEND_KEY:-$(tr -d '[:space:]' < .secrets/resend-key 2>/dev/null || true)}"

earwig_write_info_plist() {
    cat > "$1/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Earwig</string>
    <key>CFBundleIdentifier</key><string>io.darkin.earwig</string>
    <key>CFBundleName</key><string>Earwig</string>
    <key>CFBundleDisplayName</key><string>Earwig</string>
    <key>CFBundleVersion</key><string>${EARWIG_BUILD}</string>
    <key>CFBundleShortVersionString</key><string>${EARWIG_VERSION}</string>
    <key>EarwigGitSHA</key><string>${EARWIG_SHA}</string>
    <key>EarwigResendKey</key><string>${EARWIG_RESEND_KEY}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIconName</key><string>AppIcon</string>
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
}

# Assemble Earwig.app at $2 from the built binary $1 (code + icon + plist only — no user data).
earwig_assemble_app() {
    local bin="$1" app="$2"
    rm -rf "$app"
    mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
    cp "$bin" "$app/Contents/MacOS/Earwig"
    cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
    earwig_write_info_plist "$app"
}
