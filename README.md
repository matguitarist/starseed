# Starseed

*A mod manager for Stardew Valley on macOS.* (Formerly "Stardew Mod Manager".)

A native macOS (SwiftUI) mod manager for SMAPI mods, built because the
official Nexus Mods app doesn't support macOS. Browse and install mods
from Nexus Mods, get update notifications, or install archives you
downloaded yourself. Browsing and local installs need no account.

## Features

- **Browse & search Nexus Mods** inside the app (thumbnails, endorsements,
  downloads, files per mod). No account needed to browse.
- **Install from Nexus**:
  - *Premium* accounts: click **Install** on any file.
  - *Free* accounts: click **Download…** and the Nexus page opens in the
    app's own browser. Click "Slow download" and the mod installs
    automatically. Sign in to Nexus once in that browser; the login is
    remembered.
- **Collections**: browse and search Stardew Valley collections on Nexus.
  Each collection shows which of its mods you already have, which are
  older than the collection's version, and which are missing. Install the
  exact files it pins (optional mods are opt-in; newer versions you
  already have are kept unless you choose otherwise), and save it as a
  profile. "Add to Vortex"/mod-manager collection links (`nxm://…/collections/…`)
  open here too.
- **SMAPI log viewer**: reads `~/.config/StardewValley/ErrorLogs/SMAPI-latest.txt`
  (or the crash log, or any log file). Levels are color-coded (trace,
  debug, info, warning, error, alert) and can be toggled with chips that
  show their counts. A "Problems" bar groups warnings and errors by mod,
  with search and live follow while the game runs. "Upload to smapi.io"
  copies the log and opens smapi.io/log.
- **Saves → missing mods**: pick a save (e.g. one copied from another
  computer) to see which mods it needs. Mod IDs stored in the save are
  matched through SMAPI's mod database, or on Nexus by author and name. If
  your last game session loaded that save, the locations and NPCs the game
  dropped ("Ignored unknown location…" in the SMAPI log) are grouped by
  mod (Ridgeside, East Scarp…) and matched on Nexus too. Tick and install.
  The SMAPI Log view links here when it sees dropped content. Each match
  shows its Nexus mod number (e.g. **#7286** = nexusmods.com/stardewvalley/mods/7286,
  Ridgeside Village). If a match is wrong, **Change…** lets you paste the
  right Nexus link or number.
- **Save backups**: back up one save or all of them, and restore a whole
  backup or a single save from it. SMAPI's automatic daily backups (from
  its Save Backup mod) are listed too. Before a restore, the current
  version is backed up ("Before restore") and moved to the Trash, so a
  restore can be undone. Restoring is blocked while the game is running.
  Backups live in `~/Library/Application Support/StardewModManager/SaveBackups/`.
  **Play** also backs up every save first when the enabled mods (or their
  versions) changed since the last Play, keeping the last 5 of these
  (Settings → General → Saves turns it off).
- **My Collections**: save your installed mods (with versions and Nexus
  numbers) as a named list, then **Export** it as a `.json` file and
  **Import** it on another Mac or share it with a friend. A collection
  shows what's installed, older or missing here, **Install** fetches the
  missing ones from Nexus, and **Use This Set** enables exactly those mods
  like a profile.
- **Nexus mod numbers everywhere**: mods show their `#ID`, matching the
  website's address. Paste a Nexus link, `#7286` or `7286` into Browse's
  search to open that mod directly.
- **SMAPI version check**: reads the installed SMAPI and game versions
  from the game folder, compares SMAPI with the latest release on Nexus,
  and flags mods whose `MinimumApiVersion` is newer than your SMAPI. A
  downloaded SMAPI installer is unpacked to Downloads and shown in Finder
  (SMAPI must be installed with its own installer).
- **Built-in Nexus browser**: every web link opens inside the app. It
  catches "Mod Manager Download" (`nxm://`) links and direct archive
  downloads and installs them.
- **Update checks** for every installed mod through SMAPI's own update API
  (Nexus, GitHub, ModDrop, CurseForge, Chucklefish), with an **Updates**
  list, badges in the mod table, and **Update All**. Premium accounts
  install every update in one go; free accounts get a guided queue that
  opens each mod's download page in turn.
  **What's New** shows the Nexus changelog between your version and the
  update (the mod page's changelog with an API key, else the files').
- **Requirements**: lists missing framework mods (e.g. Content Patcher)
  and which mods need them. **Install All** enables disabled copies and
  downloads the rest. Nexus IDs come from SMAPI's mod database. After an
  install, the app offers to fetch any new requirements. Each Nexus mod
  page also shows its requirements, with installed/missing status.
- **Mods in subfolders**: like SMAPI, folders without a manifest are
  searched for mods (`Mods/Expansions/SVE`), and a dot-prefixed folder
  disables everything inside it. Updates replace a mod where it is, even
  in a subfolder, instead of adding a second copy.
- **Multi-part mods as one entry**: parts in the same folder, with the same
  Nexus number, or with the same name once tags are removed ("[CP] X",
  "X Code") are grouped. Expand to see the parts; one checkbox turns the
  whole mod on or off.
- **Clean up after deleting**: when you remove a mod, the app lists its
  requirements that nothing else uses anymore (e.g. tilesheet packs left
  behind by an expansion) and offers to move them to the Trash too. Only
  required dependencies count, a requirement still needed by any other
  mod (even a disabled one) is kept, and SMAPI's bundled mods are never
  suggested.
- **Duplicate detection**: two enabled copies of one mod (SMAPI skips both)
  are flagged, and **Keep Newest** trashes the older copy.
- **Rollback**: updates keep the replaced version (last 3 per mod in
  `~/Library/Application Support/StardewModManager/ModArchive/`). **Revert**
  in the details panel puts it back, with your current settings.
- **Mod settings editor**: edit a mod's `config.json` as a form (switches,
  number and text fields, nested sections) or as raw JSON. Key order and
  number formatting are kept, and the previous file is saved as
  `config.json.bak`.
- **Mods per save**: link a profile or collection to a save; **Use Mods &
  Play** switches to it and launches the game.
- **Log insights**: the SMAPI log explains skipped mods (missing
  requirements, SMAPI too old), mods that keep erroring, and available
  updates in plain words, with buttons to fix them.
- **Background update checks**: every few hours, with a macOS notification
  for new updates, and an optional menu bar icon (Play, updates, missing
  requirements). Configure in Settings → General.
- **Endorse & track** mods on Nexus from the app (needs your API key; Nexus
  only accepts endorsements for mods you've downloaded).
- Sortable table with checkboxes to enable/disable mods (multi-select +
  right-click to toggle many at once). Uses SMAPI's leading-dot convention
  (`ModName` ↔ `.ModName`), so no files are moved out of the Mods folder.
- Flags mods with a missing/invalid `manifest.json` or a missing required
  dependency (including a content pack's framework)
- Install from local `.zip`, `.7z` or `.rar` files: toolbar button, drag
  and drop onto the window, or open them with the app. Handles zips that
  wrap the real mod folder in an extra directory.
- Updating a mod keeps its `config.json` and enabled/disabled state; old
  versions and deleted mods go to the Trash.
- Profiles: save named sets of enabled mods and switch between them
- Open Mods folder in Finder, launch the game via Steam

## Downloading from Nexus: setup

1. Open **Settings → Nexus Mods** (⌘,). Click **Open the Nexus API Keys
   page…**, sign in, copy your **Personal API Key**, then click **Paste**
   and **Save & Verify**. The key is stored in the macOS Keychain.
   (Locally built apps are re-signed on every build, so macOS asks for
   Keychain access again after each rebuild. Choose "Always Allow". To stop
   this, add your Apple ID in Xcode → Settings → Accounts and build with
   `DEVELOPMENT_TEAM=<your team ID> ./build_app.sh`.)
2. Optional: make the app the default handler for "Mod Manager Download"
   (`nxm://`) links, so clicks in Safari or Chrome also land here.

> **Why Nexus and not CurseForge?** Nearly all Stardew Valley mods are
> published on Nexus, and SMAPI's update keys point there. CurseForge's
> API requires each app developer to apply for a private API key, so
> it isn't supported for now.
>
> **API policy:** Nexus allows personal API keys for personal and testing
> use. To publish this app for other people, register it with Nexus
> (support → app registration) to get an SSO application slug.

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 16 or later (tested with Xcode 27)

## Build & run

Open `StardewModManager.xcodeproj` in Xcode and press ⌘R, or ⌘U to run the
tests. From the terminal:

```bash
./build_app.sh                          # -> dist/Starseed.app
open "dist/Starseed.app"     # or drag it into /Applications
```

The project file is generated from `project.yml` with
[XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`,
then `xcodegen generate`). You only need to regenerate it after adding
files or changing build settings. Edit `project.yml`, not the `.xcodeproj`.

> **iCloud Drive note:** if this folder syncs with iCloud (e.g. it's on the
> Desktop), build products must live outside it, or `codesign` fails with
> "resource fork, Finder information, or similar detritus not allowed".
> Xcode's DerivedData and `build_app.sh` already build in `~/Library`. For
> `swift test` in `ModManagerCore/`, pass
> `--scratch-path ~/Library/Caches/StardewModManager/core-build`.
>
> Live API tests (real Nexus/SMAPI requests) are skipped unless you set
> `LIVE_API_TESTS=1`.

On first launch, the app checks for the default Steam install location:

```
~/Library/Application Support/Steam/steamapps/common/Stardew Valley/Contents/MacOS/Mods
```

If found, it offers to use it. Otherwise (GOG install, custom Steam
library location, etc.) choose your `Mods` folder manually. You can change
it later in Settings or via **Mods → Change Mods Folder…**.

> **Tip:** if you're not sure where your Mods folder is, launch the game
> through SMAPI once and check its terminal output — it prints a line
> like `[SMAPI] Mods go here: /Users/you/Library/.../Mods`.

## Project layout

```
stardew_mod_manager/
├── project.yml                   # XcodeGen spec -> StardewModManager.xcodeproj
├── StardewModManager.xcodeproj
├── build_app.sh                  # Release build -> dist/
├── App/                          # SwiftUI app target
│   ├── StardewModManagerApp.swift
│   ├── AppModel.swift            # app state + actions (install queue, downloads, updates)
│   ├── RootView.swift            # sidebar, drop target, alerts
│   ├── InstalledView.swift       # mod table + toolbar
│   ├── ModDetailView.swift       # inspector pane
│   ├── UpdatesView.swift         # updates + Update All
│   ├── RequirementsView.swift    # missing dependencies
│   ├── BrowserView.swift         # in-app Nexus browser (WKWebView)
│   ├── CollectionsView.swift / CollectionSheet.swift
│   ├── LogViewerView.swift       # SMAPI log viewer
│   ├── SavesView.swift           # saves: missing-mod analysis, backups/restore
│   ├── MyCollectionsView.swift   # saved/exported mod lists
│   ├── ConfigEditorView.swift    # config.json form editor
│   ├── Background.swift          # background checks, notifications, menu bar
│   ├── BrowseView.swift          # Nexus search
│   ├── NexusModSheet.swift       # mod details + file list
│   ├── SettingsView.swift        # Mods folder, Nexus API key, nxm handler
│   ├── ProfilesView.swift
│   ├── Downloads.swift / Keychain.swift
│   └── Info.plist                # generated by XcodeGen (registers nxm://)
├── ModManagerCore/               # local Swift package, no UI
│   ├── Sources/ModManagerCore/
│   │   ├── Models.swift          # ModInfo + manifest parsing
│   │   ├── ModManager.swift      # scan/enable/disable/install/trash
│   │   ├── ConfigStore.swift     # settings + profiles
│   │   ├── NexusClient.swift     # Nexus GraphQL (browse) + REST (downloads)
│   │   ├── UpdateChecker.swift   # SMAPI update API + UniqueID → Nexus lookup
│   │   ├── Dependencies.swift    # missing-dependency grouping, file picking
│   │   ├── Collections.swift     # Nexus collections (GraphQL)
│   │   ├── SMAPI.swift           # semantic versions, installed SMAPI/game version
│   │   ├── SMAPILog.swift        # SMAPI log parser
│   │   ├── Saves.swift           # save list, mod IDs in saves, missing-content matching
│   │   ├── SaveBackups.swift     # save backup/restore (zip, SMAPI-compatible)
│   │   ├── ModList.swift         # My Collections: snapshot, export/import, compare
│   │   ├── ModGrouping.swift     # multi-part mod grouping
│   │   ├── ModArchive.swift      # previous versions for rollback
│   │   ├── ConfigJSON.swift      # order-preserving JSON5-lite reader/writer
│   │   ├── LogInsights.swift     # plain-language findings from SMAPI logs
│   │   └── FileDownloader.swift
│   └── Tests/ModManagerCoreTests/
└── legacy-python/               # original PySide6 version, kept for reference
```

App settings and profiles are stored at
`~/Library/Application Support/StardewModManager/` — separate from the
game, and in the same format as the old Python version.

## Releasing updates (Sparkle)

The app updates itself with [Sparkle](https://sparkle-project.org). It stays
off until `SUFeedURL` and `SUPublicEDKey` are set in `project.yml`; then
**Starseed → Check for App Updates…** and a Settings toggle appear.

One-time setup:

1. Create the signing key (the private half goes into your login Keychain):
   ```bash
   ~/Library/Caches/StardewModManager/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys
   ```
   Put the printed public key in `SUPublicEDKey`. Back up the private key
   (`generate_keys -x key.txt`): without it, existing users can't be updated.
2. Choose where releases live, e.g. GitHub Releases for the zips and
   GitHub Pages for `appcast.xml`, and put the appcast's URL in `SUFeedURL`.
3. `xcodegen generate`.

Each release:

1. Bump `MARKETING_VERSION` **and** `CURRENT_PROJECT_VERSION` in
   `project.yml` (Sparkle compares the build number), then `xcodegen generate`.
2. `./build_app.sh` (ideally signed with a Developer ID and notarized, or
   macOS warns people on first launch).
3. Zip it and generate the appcast:
   ```bash
   mkdir -p releases
   ditto -c -k --keepParent "dist/Starseed.app" "releases/Starseed-2.2.zip"
   ~/Library/Caches/StardewModManager/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast releases
   ```
4. Upload the zip and `releases/appcast.xml` to the places from step 2.

## Languages

English and French. Strings live in String Catalogs
(`App/Localizable.xcstrings`, `App/InfoPlist.xcstrings`, and
`ModManagerCore/Sources/ModManagerCore/Resources/Localizable.xcstrings`).
To update translations after changing text:

```bash
xcodebuild -exportLocalizations -project StardewModManager.xcodeproj -localizationPath l10n -exportLanguage fr
# edit l10n/fr.xcloc/Localized Contents/fr.xliff (or open the .xcloc in Xcode)
xcodebuild -importLocalizations -project StardewModManager.xcodeproj -localizationPath l10n/fr.xcloc
```

To add a language (German, say): add `de` to `CFBundleLocalizations` in
`project.yml`, run `xcodegen generate`, then export with `-exportLanguage de`,
translate, and import. Settings → General → Language lists every
translation in the app automatically, named in its own language.

## Notes / known limitations

- Free Nexus accounts need one click per mod ("Slow download" in the
  built-in browser): Nexus only gives direct API downloads to Premium
  members.
- Dependency checks don't compare minimum versions from manifests yet,
  only whether the dependency is installed and enabled.
- Update All picks the main file whose version matches the update (else
  the newest main file). For mods with several main variants, use
  **Files…** to choose one.
- Signing in with Google or Apple inside the built-in browser may be
  blocked by those providers. Use Nexus email/password login, or click
  "Mod Manager Download" in your normal browser with the app set as the
  `nxm://` handler.
- Deleting a mod moves its folder to the Trash. Updating a mod also sends
  the old version to the Trash, keeping its `config.json` settings.
