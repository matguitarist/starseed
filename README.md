# Starseed

[![Tests](https://github.com/matguitarist/starseed/actions/workflows/tests.yml/badge.svg)](https://github.com/matguitarist/starseed/actions/workflows/tests.yml)

*A mod manager for Stardew Valley on macOS.*

Install, update and organize your Stardew Valley mods on a Mac: browse
Nexus Mods, install mods and whole collections, keep everything up to date,
and find out quickly what's wrong when the game misbehaves.

**[Download Starseed for Mac](https://github.com/matguitarist/starseed/releases/latest/download/Starseed.dmg)**
(macOS 14 Sonoma or later)

![Starseed's Installed list with mod pictures, and Stardew Valley Expanded's details](docs/screenshots/installed.png)

## Install

1. Open the disk image and drag **Starseed** onto **Applications**.
2. The first time, macOS says it can't check Starseed, because it isn't
   signed with a paid Apple Developer ID. Open **System Settings → Privacy &
   Security**, scroll down, and click **Open Anyway**. This is needed only once:
   Starseed updates itself after that.

## Getting started

1. **Mods folder:** for the Steam version, Starseed offers the game's `Mods`
   folder on first launch. For other installs, choose it yourself.
2. **SMAPI:** mods run through SMAPI, the Stardew Valley mod loader. If it's
   missing, click **Install SMAPI** in the orange banner.
3. **Nexus Mods:** to download mods in the app, paste your personal API key in
   **Settings → Nexus Mods** (the **Open the Nexus API Keys page…** button
   takes you there). Browsing works without it.
   - *Premium* accounts download directly.
   - *Free* accounts click **Slow download** once per mod on the Nexus page
     that opens in Starseed, and the mod installs itself.
4. Press **Play**.

Everything else is explained in **Help → Starseed Help** (⌘?).

## A quick tour

**Your mods at a glance.** Every mod in your Mods folder with its picture,
version and status. Multi-part mods like Stardew Valley Expanded show as one
row. The details panel shows what a mod needs, which mods use it, and any
conflicts. At the bottom, green, yellow or red dots tell you whether the game
and SMAPI are up to date, with one-click updates.

**Find and install mods from Nexus.** Search or browse the most popular mods,
see their requirements, and install them along with what they need. Updates
show up in the list; read what's new, then update in one click.

![Browsing Stardew Valley mods on Nexus](docs/screenshots/browse.png)

**Install whole collections.** Nexus collections (curated mod packs) install
every mod at the versions they were made with.

![Nexus collections in Starseed](docs/screenshots/collections.png)

**When something breaks.** After you play, Starseed tells you if mods failed
to load, had errors or conflicted, in plain words with a button to fix each
one. If the log doesn't say which mod is to blame, **Find a Broken Mod**
narrows it down in a few launches.

**Keep your farms safe.** Saves are backed up before you play with changed
mods, each farm can have its own set of mods, and earlier mod versions are
kept so an update can be rolled back.

![Starseed's Help window](docs/screenshots/help.png)

## Everything it does

**Installing**
- Browse and search Nexus Mods, see each mod's files and requirements, and
  install with what it needs.
- Install Nexus collections, or your own mod archives (.zip, .7z, .rar) by
  dropping them on the window.
- Install, update and reconnect SMAPI in one click.
- Mods that aren't on Nexus (ModDrop, GitHub…) get a button to their page.

**Keeping up to date**
- Checks every mod for updates at launch and every few hours, with
  notifications and an optional menu bar icon.
- Read what's new before updating, update one mod or all of them.
- Every update keeps the previous version, so you can roll back.
- Tells you when Steam has a game update waiting.

**Organizing**
- Turn mods on and off (⌘Z undoes it), with multi-part mods kept together.
- Profiles for different ways of playing, and a set of mods for each farm.
- Export a profile (mods, versions and settings) and import it on another Mac
  or share it with a friend; missing mods download into it.
- Edit a mod's settings in a simple form.
- Spots mods installed twice, missing requirements, and requirements nothing
  uses anymore after you remove a mod.
- Settings → Storage shows what takes space and cleans up old versions and
  backups.

**When something goes wrong**
- A readable SMAPI log with colors, filters and plain-language advice.
- A report after each game session: mods that didn't load, had errors,
  conflicted or crashed the game.
- Find a Broken Mod: a guided search that names the culprit in a few tests.
- Finds which mods a save needs, for example a farm copied from another
  computer, and installs the missing ones.
- Save backups: back up and restore one farm or all of them; Play backs up
  your saves when your mods changed.
- Each farm remembers the profile it's played with, and Play from Saves
  switches to it first.

**Languages:** English, French, German, Spanish, Brazilian Portuguese and
Simplified Chinese (Settings → General → Language).

## Good to know

- Free Nexus accounts need one click per mod ("Slow download"): Nexus only
  allows direct downloads in apps for Premium members.
- Signing in to Nexus with Google or Apple inside Starseed's browser may be
  blocked by those services. Use your Nexus email and password, or set
  Starseed as the handler for "Mod Manager Download" links (Settings → Nexus
  Mods) and click them in your usual browser.
- Removed mods and old versions go to the Trash, so they can be recovered.
- Starseed keeps its settings, collections, kept versions and save backups in
  `~/Library/Application Support/StardewModManager/`.

## Help and feedback

- In the app: **Help → Starseed Help** (⌘?).
- Found a bug or have an idea? [Open an issue](https://github.com/matguitarist/starseed/issues/new/choose)
  (English or French is fine).
- Building it yourself or contributing: see [DEVELOPMENT.md](DEVELOPMENT.md).

Starseed is free and open source (MIT license). It isn't affiliated with
ConcernedApe, SMAPI or Nexus Mods.
