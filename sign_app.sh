#!/bin/zsh
# Signs a built Starseed.app: with your "Developer ID Application" certificate
# when it's in the Keychain (then notarize.sh can get Apple's approval), else
# with the self-signed certificate made by make_signing_identity.sh. Either
# keeps the app's identity the same from build to build, so macOS asks for
# Keychain access once instead of after every update.
#
# Usage: ./sign_app.sh path/to/Starseed.app   (SIGNING_IDENTITY overrides)
# Signs inside out, as Sparkle's documentation describes: its helpers, the
# framework, then the app with its own entitlements.
set -euo pipefail

APP="$1"
IDENTITY="${SIGNING_IDENTITY:-$("${0:A:h}/signing_identity.sh")}"
KEYCHAIN_ARGS=()
[[ -n "${SIGNING_KEYCHAIN:-}" ]] && KEYCHAIN_ARGS=(--keychain "$SIGNING_KEYCHAIN")
# Notarization needs Apple's secure timestamp; the self-signed one can't
# be notarized, so it skips the round trip to Apple.
TIMESTAMP=(--timestamp=none)
[[ "$IDENTITY" == "Developer ID Application:"* ]] && TIMESTAMP=(--timestamp)

sign() { codesign --force "${TIMESTAMP[@]}" --options runtime --sign "$IDENTITY" "${KEYCHAIN_ARGS[@]}" "$@" }

# Extended attributes (Finder info, iCloud) make codesign fail.
xattr -cr "$APP"

SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
if [[ -d "$SPARKLE" ]]; then
    sign "$SPARKLE/XPCServices/Installer.xpc"
    sign --preserve-metadata=entitlements "$SPARKLE/XPCServices/Downloader.xpc"
    sign "$SPARKLE/Autoupdate"
    sign "$SPARKLE/Updater.app"
    sign "$APP/Contents/Frameworks/Sparkle.framework"
fi

# The app keeps the entitlements Xcode gave it, except get-task-allow:
# "Sign to Run Locally" adds it for debugging, and a release shouldn't let
# other processes attach to it.
ENTITLEMENTS=$(mktemp -t starseed-entitlements).plist
codesign -d --entitlements - --xml "$APP" > "$ENTITLEMENTS" 2>/dev/null
/usr/libexec/PlistBuddy -c "Delete :com.apple.security.get-task-allow" "$ENTITLEMENTS" >/dev/null 2>&1 || true
sign --entitlements "$ENTITLEMENTS" "$APP"
rm -f "$ENTITLEMENTS"

codesign --verify --deep --strict "$APP"
echo "Signed $APP with “$IDENTITY”"
