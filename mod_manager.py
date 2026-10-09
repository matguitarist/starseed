"""
mod_manager.py
---------------
All filesystem operations on the Mods folder live here, kept separate from
the Qt UI code so the logic can be tested/reused on its own.

Enable/disable convention: SMAPI natively skips any folder in Mods whose
name starts with a dot. We toggle that dot to enable/disable a mod without
ever deleting or moving files out of the Mods folder.
"""

from __future__ import annotations

import shutil
import subprocess
import sys
import tempfile
import zipfile
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

from models import ModInfo, parse_manifest


class ModManagerError(Exception):
    """Raised for expected, user-facing problems (bad zip, missing folder, etc)."""


@dataclass
class InstallResult:
    installed: list[str]      # mod names successfully installed/updated
    skipped: list[str]        # mod names the user chose not to overwrite
    errors: list[str]         # human-readable error messages


class ModManager:
    def __init__(self, mods_path: Path):
        self.mods_path = mods_path

    # ------------------------------------------------------------------ #
    # Scanning
    # ------------------------------------------------------------------ #

    def scan(self) -> list[ModInfo]:
        """Read every top-level folder in Mods/ and parse its manifest.json."""
        if not self.mods_path.exists():
            raise ModManagerError(f"Mods folder does not exist:\n{self.mods_path}")

        mods: list[ModInfo] = []
        for entry in sorted(self.mods_path.iterdir(), key=lambda p: p.name.lower()):
            if not entry.is_dir():
                continue
            mods.append(parse_manifest(entry, entry.name))

        self._mark_missing_dependencies(mods)
        return mods

    @staticmethod
    def _mark_missing_dependencies(mods: list[ModInfo]) -> None:
        """Flag any required dependency that isn't present & enabled among the scanned mods."""
        enabled_ids = {m.unique_id.lower() for m in mods if m.enabled and m.unique_id}
        for mod in mods:
            missing = [
                dep.unique_id
                for dep in mod.dependencies
                if dep.required and dep.unique_id.lower() not in enabled_ids
            ]
            mod.missing_dependencies = missing

    # ------------------------------------------------------------------ #
    # Enable / disable / delete
    # ------------------------------------------------------------------ #

    def set_enabled(self, mod: ModInfo, enabled: bool) -> Path:
        """Rename the mod's folder to add/remove the leading dot. Returns the new path."""
        bare_name = mod.folder_name.lstrip(".")
        new_name = bare_name if enabled else f".{bare_name}"
        new_path = self.mods_path / new_name

        if new_path == mod.folder_path:
            return mod.folder_path  # already in the desired state

        if new_path.exists():
            raise ModManagerError(
                f"Can't rename — a folder named '{new_name}' already exists."
            )

        mod.folder_path.rename(new_path)
        return new_path

    def delete_mod(self, mod: ModInfo) -> None:
        shutil.rmtree(mod.folder_path)

    def open_in_finder(self, path: Optional[Path] = None) -> None:
        target = path or self.mods_path
        if sys.platform == "darwin":
            subprocess.run(["open", str(target)], check=False)
        elif sys.platform.startswith("linux"):
            subprocess.run(["xdg-open", str(target)], check=False)
        else:
            subprocess.run(["explorer", str(target)], check=False)

    # ------------------------------------------------------------------ #
    # Installing from a downloaded .zip
    # ------------------------------------------------------------------ #

    def find_mod_roots_in_zip(self, zip_path: Path, extract_to: Path) -> list[Path]:
        """
        Extract a zip and return the folder(s) inside it that directly contain
        a manifest.json. Handles the common case where Nexus zips wrap the
        real mod folder in an extra top-level directory.
        """
        with zipfile.ZipFile(zip_path) as zf:
            zf.extractall(extract_to)

        roots = []
        for manifest in extract_to.rglob("manifest.json"):
            roots.append(manifest.parent)
        return roots

    def install_from_zip(
        self,
        zip_path: Path,
        overwrite_decision,  # callable(existing_name: str) -> bool, asks the user
    ) -> InstallResult:
        """
        Install every mod found inside a .zip into the Mods folder.
        `overwrite_decision` is called once per name collision so the UI
        layer can show a confirmation dialog instead of this module
        silently overwriting anything.
        """
        result = InstallResult(installed=[], skipped=[], errors=[])

        with tempfile.TemporaryDirectory(prefix="sdv_mod_") as tmp:
            tmp_path = Path(tmp)
            try:
                roots = self.find_mod_roots_in_zip(zip_path, tmp_path)
            except zipfile.BadZipFile:
                result.errors.append(f"{zip_path.name} is not a valid zip file.")
                return result

            if not roots:
                result.errors.append(
                    f"No manifest.json found anywhere inside {zip_path.name} — "
                    "this may not be a SMAPI mod (could be an XNB/content-only mod)."
                )
                return result

            for root in roots:
                mod_name = root.name
                dest_enabled = self.mods_path / mod_name
                dest_disabled = self.mods_path / f".{mod_name}"
                existing = dest_enabled if dest_enabled.exists() else (
                    dest_disabled if dest_disabled.exists() else None
                )

                if existing is not None:
                    if not overwrite_decision(mod_name):
                        result.skipped.append(mod_name)
                        continue
                    shutil.rmtree(existing)
                    dest = existing  # preserve previous enabled/disabled state
                else:
                    dest = dest_enabled

                try:
                    shutil.copytree(root, dest)
                    result.installed.append(mod_name)
                except OSError as exc:
                    result.errors.append(f"{mod_name}: {exc}")

        return result

    # ------------------------------------------------------------------ #
    # Launching the game
    # ------------------------------------------------------------------ #

    @staticmethod
    def launch_via_steam(app_id: str) -> None:
        """
        On macOS, SMAPI's installer replaces the game's own launcher, so a
        normal Steam launch already runs through SMAPI — no special launch
        options are needed (unlike on Windows).
        """
        if sys.platform == "darwin":
            subprocess.run(["open", f"steam://rungameid/{app_id}"], check=False)
        else:
            subprocess.run(["xdg-open", f"steam://rungameid/{app_id}"], check=False)
