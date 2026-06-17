#!/bin/bash
# Creates a stable self-signed code-signing identity ("Earwig Dev Signing") in the
# login keychain. Signing every build with the SAME identity gives Earwig.app a stable
# designated requirement, so macOS TCC permission grants (microphone, system audio,
# speech recognition) survive rebuilds instead of resetting on every ad-hoc signature.
#
# Idempotent: does nothing if the identity already exists. Run once per machine:
#   ./scripts/create-signing-identity.sh
set -euo pipefail

NAME="Earwig Dev Signing"
KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$NAME"; then
    echo "Identity '$NAME' already present — nothing to do."
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/ext.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = $NAME
[v3]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:false
EOF

# Self-signed cert + key with the codeSigning EKU that `codesign` requires.
openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
    -days 3650 -config "$TMP/ext.cnf" >/dev/null 2>&1

# `-legacy` (RC2/3DES + SHA1 MAC) is required: macOS's keychain importer rejects the
# SHA256-MAC PKCS12 that OpenSSL 3 produces by default.
openssl pkcs12 -export -legacy -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -name "$NAME" -out "$TMP/identity.p12" -passout pass:earwig >/dev/null 2>&1

# Import the identity and authorise codesign/security to use the private key without
# repeated keychain prompts.
security import "$TMP/identity.p12" -k "$KEYCHAIN" -P earwig \
    -T /usr/bin/codesign -T /usr/bin/security
security set-key-partition-list -S apple-tool:,apple: -s -k "" "$KEYCHAIN" >/dev/null 2>&1 || true

echo "Created '$NAME'. Verifying…"
security find-identity -v -p codesigning | grep "$NAME"
