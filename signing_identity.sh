#!/bin/zsh
# Prints the certificate to sign with: your "Developer ID Application" one
# (Xcode → Settings → Accounts → Manage Certificates) if it's in the
# Keychain, else "Starseed Self-Signed" (make_signing_identity.sh), else
# nothing.
set -euo pipefail
IDENTITIES=$(security find-identity -v -p codesigning; security find-identity -p codesigning)
DEVELOPER_ID=$(print -r -- "$IDENTITIES" | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"' || true)
if [[ -n "$DEVELOPER_ID" ]]; then
    print -r -- "$DEVELOPER_ID"
elif print -r -- "$IDENTITIES" | grep -q '"Starseed Self-Signed"'; then
    print -r -- "Starseed Self-Signed"
fi
