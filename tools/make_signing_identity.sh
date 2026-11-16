#!/bin/zsh
# Creates "Starseed Self-Signed", the certificate releases are signed with,
# in your login Keychain. Run it once, on the Mac you release from.
#
# Why: an ad-hoc signature changes with every build, so macOS asks users for
# Keychain access (their Nexus API key) again after each update. Signed with
# the same certificate, the app keeps its identity: "Always Allow" sticks.
# It doesn't replace Apple notarization: first installs still go through
# System Settings → Privacy & Security → Open Anyway.
#
# Back the certificate up (Keychain Access → My Certificates → right-click
# "Starseed Self-Signed" → Export…). If it's lost, make a new one: updates
# keep working, but users are asked for Keychain access once more.
set -euo pipefail

NAME="Starseed Self-Signed"
if security find-identity -p codesigning | grep -q "\"$NAME\""; then
    echo "“$NAME” is already in your Keychain."
    exit 0
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cat > "$WORK/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CNF

# macOS's own LibreSSL: Homebrew's OpenSSL 3+ writes .p12 files the
# Keychain can't import.
OPENSSL=/usr/bin/openssl
PASS=$(uuidgen)
$OPENSSL req -x509 -newkey rsa:2048 -nodes -days 7300 -config "$WORK/cert.cnf" \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null
$OPENSSL pkcs12 -export -name "$NAME" -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -out "$WORK/identity.p12" -passout "pass:$PASS"
security import "$WORK/identity.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
    -P "$PASS" -T /usr/bin/codesign >/dev/null

echo "Created “$NAME” in your login Keychain."
echo "The first build asks to let codesign use it: click Always Allow."
echo "Back it up: Keychain Access → My Certificates → “$NAME” → Export…"
