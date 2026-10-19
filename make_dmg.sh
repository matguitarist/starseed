#!/bin/bash
# Packs dist/Starseed.app into a drag-to-install disk image:
#   ./make_dmg.sh releases/Starseed.dmg
# The window shows the app, an Applications shortcut, and (unless
# NOTARIZED=1) a note about macOS's warning for apps that aren't notarized.
set -euo pipefail
cd "$(dirname "$0")"

OUT="${1:-releases/Starseed.dmg}"
APP="dist/Starseed.app"
[ -d "$APP" ] || { echo "Build the app first (./build_app.sh)." >&2; exit 1; }

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
# No extended attributes: they break the app's code signature check.
ditto --noextattr --norsrc "$APP" "$STAGE/Starseed.app"
xattr -cr "$STAGE/Starseed.app"
ln -s /Applications "$STAGE/Applications"
# Notarized apps open without a warning: the note is for the others.
[ -n "${NOTARIZED:-}" ] || cat > "$STAGE/If macOS blocks Starseed.txt" <<'NOTE'
Install: drag Starseed onto the Applications folder.

The first time you open it, macOS may say it can't check Starseed for
malicious software, because it isn't signed with a paid Apple Developer ID.
To open it anyway:

  1. Try to open Starseed once, then click Done.
  2. Open System Settings > Privacy & Security.
  3. Scroll down and click "Open Anyway" next to Starseed, then confirm.

You only do this once; updates install without asking again.

---

Installation : glissez Starseed sur le dossier Applications.

À la première ouverture, macOS peut dire qu'il ne peut pas vérifier
Starseed, car l'app n'est pas signée avec un identifiant de développeur
Apple payant. Pour l'ouvrir quand même :

  1. Essayez d'ouvrir Starseed une fois, puis cliquez sur Terminé.
  2. Ouvrez Réglages Système > Confidentialité et sécurité.
  3. Faites défiler et cliquez sur « Ouvrir quand même » à côté de
     Starseed, puis confirmez.

Une seule fois suffit : les mises à jour s'installent ensuite sans
redemander.
NOTE

mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"
hdiutil create -volname "Starseed" -srcfolder "$STAGE" -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$OUT" >/dev/null 2>&1
echo "Created $OUT"
