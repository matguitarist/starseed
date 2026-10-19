#!/bin/zsh
# Builds a Release "dist/Starseed.app" with Xcode.
#
# Build products go to ~/Library/Caches (not next to the sources): this
# folder may sync with iCloud Drive, whose extended attributes make
# codesign fail ("resource fork, Finder information, or similar detritus").
set -euo pipefail
cd "${0:A:h}"

# Use full Xcode even if xcode-select still points at the Command Line Tools.
if ! xcodebuild -version >/dev/null 2>&1; then
    XCODE_APP=$(ls -d /Applications/Xcode*.app 2>/dev/null | grep -v Xcodes.app | sort -V | tail -1)
    export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
fi

# Optional: DEVELOPMENT_TEAM=XXXXXXXXXX ./build_app.sh signs with your Apple
# Development certificate (add your Apple ID in Xcode → Settings → Accounts).
# A stable signature means macOS asks for Keychain access only once instead
# of after every rebuild.
SIGNING=()
if [[ -n "${DEVELOPMENT_TEAM:-}" ]]; then
    SIGNING=(DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" CODE_SIGN_IDENTITY="Apple Development" -allowProvisioningUpdates)
fi

DERIVED="$HOME/Library/Caches/StardewModManager/DerivedData"
LOG="$DERIVED/build_app.log"
mkdir -p "$DERIVED"
# A failed build must stop here: an older app would still be in DerivedData.
if ! xcodebuild -project StardewModManager.xcodeproj -scheme StardewModManager "${SIGNING[@]}" \
    -configuration Release -destination "generic/platform=macOS" -derivedDataPath "$DERIVED" build > "$LOG" 2>&1; then
    grep -E "error:" "$LOG" | head -20
    echo "Build failed (full log: $LOG)"
    exit 1
fi

APP_NAME="Starseed.app"
BUILT="$DERIVED/Build/Products/Release/$APP_NAME"
[[ -d "$BUILT" ]] || { echo "Build failed"; exit 1; }

# Signed with your Developer ID (or else the "Starseed Self-Signed"
# certificate, make_signing_identity.sh), so the app's identity stays the
# same from build to build. REQUIRE_SIGNING=1 (release.sh) stops without one.
# Signing happens here in Caches: this folder may sync with iCloud Drive,
# which puts Finder attributes back on files and makes codesign fail.
STAGED="$DERIVED/Signed/$APP_NAME"
/bin/rm -rf "$STAGED"
mkdir -p "${STAGED:h}"
ditto --noextattr --norsrc "$BUILT" "$STAGED"
if [[ -z "${DEVELOPMENT_TEAM:-}" ]]; then
    if [[ -n "$(./signing_identity.sh)" ]]; then
        ./sign_app.sh "$STAGED" 2>&1 | grep -v "replacing existing signature"
        # Notarized here, in Caches, for the same reason (release.sh asks).
        if [[ -n "${NOTARIZE:-}" ]]; then ./notarize.sh "$STAGED"; fi
    elif [[ -n "${REQUIRE_SIGNING:-}" ]]; then
        echo "No signing certificate: add your Developer ID in Xcode, or run ./make_signing_identity.sh." >&2
        exit 1
    else
        echo "Note: signed ad hoc (run ./make_signing_identity.sh for a stable signature)."
    fi
fi

mkdir -p dist
/bin/rm -rf "dist/$APP_NAME"
ditto --noextattr --norsrc "$STAGED" "dist/$APP_NAME"
echo "Built dist/$APP_NAME"
