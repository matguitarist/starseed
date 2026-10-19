#!/bin/zsh
# Sends a Developer ID-signed app or disk image to Apple's notary service,
# waits for its approval, and staples the ticket to it, so macOS opens it
# without the "can't check for malicious software" warning, even offline.
#
# Usage: ./notarize.sh path/to/Starseed.app | path/to/Starseed.dmg
# Needs the credentials saved once with:
#   xcrun notarytool store-credentials ares-notary --apple-id <you> --team-id <TEAMID>
# (NOTARY_PROFILE picks another name.)
set -euo pipefail
cd "${0:A:h}"

TARGET="$1"
PROFILE="${NOTARY_PROFILE:-ares-notary}"

# notarytool takes a zip, a disk image or a package: an app goes as a zip.
UPLOAD="$TARGET"
if [[ "$TARGET" == *.app ]]; then
    UPLOAD=$(mktemp -d)/"${TARGET:t:r}.zip"
    ditto -c -k --norsrc --noextattr --keepParent "$TARGET" "$UPLOAD"
fi

echo "==> Notarizing ${TARGET:t} (Apple usually answers within a few minutes)"
RESULT=$(xcrun notarytool submit "$UPLOAD" --keychain-profile "$PROFILE" --wait --output-format json)
STATUS=$(print -r -- "$RESULT" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin).get("status",""))')
ID=$(print -r -- "$RESULT" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin).get("id",""))')
if [[ "$STATUS" != "Accepted" ]]; then
    echo "Notarization: $STATUS. Apple's log:" >&2
    [[ -n "$ID" ]] && xcrun notarytool log "$ID" --keychain-profile "$PROFILE" >&2
    exit 1
fi

xcrun stapler staple "$TARGET" >/dev/null
xcrun stapler validate "$TARGET" >/dev/null
spctl --assess --type "$([[ "$TARGET" == *.dmg ]] && echo open || echo execute)" \
    $([[ "$TARGET" == *.dmg ]] && echo --context context:primary-signature) "$TARGET"
echo "Notarized and stapled ${TARGET:t}"
