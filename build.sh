#!/bin/bash
# Builds Earwig and packages it as Earwig.app (required so macOS can grant
# microphone / system-audio / speech-recognition permissions to the app).
# For a build to send to other people, use ./package.sh instead.
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
swift build -c "$CONFIG"

source scripts/app-meta.sh
earwig_assemble_app ".build/$CONFIG/Earwig" "Earwig.app"
echo "Version $EARWIG_VERSION (build $EARWIG_BUILD, $EARWIG_SHA)"

# Sign with the stable local identity so the app keeps one designated requirement
# across rebuilds (TCC permission grants then persist). Create it once with
# scripts/create-signing-identity.sh.
IDENTITY="Earwig Dev Signing"
if ! security find-identity 2>/dev/null | grep -q "$IDENTITY"; then
    echo "error: signing identity '$IDENTITY' not found." >&2
    echo "Run ./scripts/create-signing-identity.sh first." >&2
    exit 1
fi
codesign --force --sign "$IDENTITY" \
    --keychain "$HOME/Library/Keychains/login.keychain-db" "Earwig.app"
echo "Signed with $IDENTITY"
echo "Built Earwig.app"
