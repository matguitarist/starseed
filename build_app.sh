#!/bin/zsh
# Builds a Release "dist/Stardew Mod Manager.app" with Xcode.
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
xcodebuild -project StardewModManager.xcodeproj -scheme StardewModManager "${SIGNING[@]}" \
    -configuration Release -destination "generic/platform=macOS" -derivedDataPath "$DERIVED" build | grep -E "error:|BUILD" || true

APP_NAME="Stardew Mod Manager.app"
BUILT="$DERIVED/Build/Products/Release/$APP_NAME"
[[ -d "$BUILT" ]] || { echo "Build failed"; exit 1; }

mkdir -p dist
/bin/rm -rf "dist/$APP_NAME"
ditto --noextattr --norsrc "$BUILT" "dist/$APP_NAME"
echo "Built dist/$APP_NAME"
