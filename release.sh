#!/bin/bash
# Publishes a release of Starseed: builds it, uploads a disk image (for
# new installs) and a zip (for Sparkle updates) to GitHub Releases, and
# updates appcast.xml (the feed Sparkle checks) on main.
#
# Before running: bump MARKETING_VERSION and CURRENT_PROJECT_VERSION in
# project.yml (Sparkle compares the build number), run `xcodegen generate`,
# and commit. Needs `gh` logged in and the Sparkle key in the Keychain.
set -euo pipefail
cd "$(dirname "$0")"

REPO="matguitarist/starseed"
VERSION=$(sed -n 's/^ *MARKETING_VERSION: *"\(.*\)"/\1/p' project.yml | head -1)
BUILD=$(sed -n 's/^ *CURRENT_PROJECT_VERSION: *"\(.*\)"/\1/p' project.yml | head -1)
TAG="v$VERSION"
SPARKLE_BIN="$HOME/Library/Caches/StardewModManager/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin"

[ -n "$VERSION" ] && [ -n "$BUILD" ] || { echo "Couldn't read the version from project.yml" >&2; exit 1; }
if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "Commit your changes first." >&2; exit 1
fi
if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
    echo "$TAG is already released: bump MARKETING_VERSION and CURRENT_PROJECT_VERSION." >&2; exit 1
fi

echo "==> Releasing Starseed $VERSION (build $BUILD)"
./build_app.sh

# Only the new zip in the folder: the feed lists the latest version, which
# is all Sparkle needs.
STAGING="releases/$TAG"
rm -rf "$STAGING" && mkdir -p "$STAGING"
ZIP="$STAGING/Starseed-$VERSION.zip"
ditto -c -k --keepParent "dist/Starseed.app" "$ZIP"
"$SPARKLE_BIN/generate_appcast" --account starseed \
    --download-url-prefix "https://github.com/$REPO/releases/download/$TAG/" \
    "$STAGING"

# The disk image is for first installs. A fixed name keeps the README's
# ".../releases/latest/download/Starseed.dmg" link working. It's made after
# the appcast so generate_appcast only sees the zip.
DMG="releases/Starseed.dmg"
./make_dmg.sh "$DMG"

git push origin HEAD
gh release create "$TAG" "$DMG" "$ZIP" --repo "$REPO" --title "Starseed $VERSION" --generate-notes

# Publish the feed last, once the zip it points to is online.
cp "$STAGING/appcast.xml" appcast.xml
git add appcast.xml
git commit -m "Update appcast for $VERSION"
git push origin HEAD
echo "==> Done: https://github.com/$REPO/releases/tag/$TAG"
