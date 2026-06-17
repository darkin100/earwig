#!/bin/bash
# Builds a distributable Earwig.app and zips it to ~/Desktop/Earwig-Share for sending to people.
# Tries a universal (Apple Silicon + Intel) build, falling back to a native build if the ML
# dependencies can't cross-compile. The bundle contains code only - no meetings, transcripts,
# API keys or other personal data.
set -euo pipefail
cd "$(dirname "$0")"

source scripts/app-meta.sh

echo "Building Earwig $EARWIG_VERSION (build $EARWIG_BUILD)…"
if swift build -c release --arch arm64 --arch x86_64 >/dev/null 2>&1; then
    BINDIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
    KIND="Universal (Apple Silicon and Intel)"
else
    echo "Universal build unavailable (a dependency is Apple-Silicon-only); building native…"
    swift build -c release >/dev/null
    BINDIR="$(swift build -c release --show-bin-path)"
    KIND="Apple Silicon"
fi

APP="dist/Earwig.app"
mkdir -p dist
earwig_assemble_app "$BINDIR/Earwig" "$APP"

# Ad-hoc sign. This is not notarised, so recipients still clear the quarantine flag once (see the
# README), but a valid signature keeps the app's identity stable on their Mac.
codesign --force --sign - "$APP"

OUT="$HOME/Desktop/Earwig-Share"
rm -rf "$OUT"
mkdir -p "$OUT"
ZIP="$OUT/Earwig-$EARWIG_VERSION.zip"
ditto -c -k --keepParent "$APP" "$ZIP"

cat > "$OUT/README.txt" <<EOF
Earwig $EARWIG_VERSION (build $EARWIG_BUILD)
$KIND - macOS 15 (Sequoia) or later

Earwig is a privacy-first menu-bar app that detects online meetings, records them and
transcribes them on your Mac. Nothing leaves your machine by default.

INSTALL
1. Unzip Earwig-$EARWIG_VERSION.zip.
2. Drag Earwig.app into your Applications folder.
3. Earwig is not from the App Store, so macOS quarantines it on first launch. Clear that once:
   - Open Terminal and run:
       xattr -dr com.apple.quarantine /Applications/Earwig.app
   - Then open Earwig normally. (Alternatively, right-click the app, choose Open, and confirm.)
4. Earwig lives in the menu bar. When you join a meeting it offers to record; grant Microphone
   and "Screen & System Audio Recording" when macOS asks (System Settings > Privacy & Security).

SUMMARIES (optional)
- Local (recommended, private): install Ollama from https://ollama.com, then in Earwig open
  Settings > Summary and download the Qwen2.5 14B model (about 9 GB, needs ~16 GB of memory).
- Apple Intelligence: available on macOS 26 on Apple Silicon, nothing to download.
- Claude (cloud, best quality): paste your own Anthropic API key in Settings > Summary.

Transcripts and notes are saved to ~/MeetingNotes. Have fun.
EOF

echo
echo "Packaged: $KIND"
echo "  $ZIP"
echo "  $OUT/README.txt"
echo "Send the whole Earwig-Share folder (or just the zip + tell them about the quarantine step)."
