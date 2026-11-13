# Starseed

A native macOS mod manager for Stardew Valley (SMAPI mods, Nexus browsing,
collections, profiles, saves). SwiftUI app plus a no-UI core package.
`DEVELOPMENT.md` has the full layout, signing, languages and versioning: read
the part you need before changing those.

## Layout

- `project.yml` is the XcodeGen spec for `StardewModManager.xcodeproj`. Edit it, then `xcodegen generate`; never edit the `.xcodeproj`.
- `App/` the SwiftUI app. `AppModel.swift` holds state and actions.
- `ModManagerCore/` local Swift package, no UI: models, Nexus and SMAPI clients, saves, profiles. Tests in `ModManagerCore/Tests/ModManagerCoreTests/`.
- `legacy-python/` the original PySide6 version, kept for reference only. Don't change it.
- Settings and profiles: `~/Library/Application Support/StardewModManager/`, in the old Python version's format. Never test against the real one.

## Build and check

- Build: `./build_app.sh` → `dist/Starseed.app`.
- Core tests: `swift test --package-path ModManagerCore --scratch-path ~/Library/Caches/StardewModManager/core-build`. Live Nexus/SMAPI tests run only with `LIVE_API_TESTS=1`.
- Strings live in String Catalogs, in six languages; new user-facing text needs every language (see Languages in `DEVELOPMENT.md`).
- Logs use LogKit (the `log-viewer` skill).
- Release: `tools/release.sh <version>` (settings in `release.conf`). Use the mac-release skill; version rules are in `DEVELOPMENT.md`.

## Git

- Commit after each working change, with a message that says what the user can now do.
