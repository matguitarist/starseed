"""
models.py
---------
Plain data structures for representing a SMAPI mod, plus the logic for
turning a mod folder's manifest.json into a ModInfo instance.

SMAPI's manifest schema reference:
https://stardewvalleywiki.com/Modding:Modder_Guide/APIs/Manifest
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional


@dataclass
class Dependency:
    unique_id: str
    required: bool = True


@dataclass
class ModInfo:
    folder_path: Path                      # absolute path to the mod's folder right now
    folder_name: str                       # current folder name, e.g. ".CJBCheats" if disabled
    name: str = "(unknown)"
    version: str = "?"
    author: str = "?"
    description: str = ""
    unique_id: str = ""
    content_pack_for: Optional[str] = None
    dependencies: list[Dependency] = field(default_factory=list)
    update_keys: list[str] = field(default_factory=list)
    enabled: bool = True
    has_manifest: bool = True
    parse_error: Optional[str] = None
    missing_dependencies: list[str] = field(default_factory=list)  # filled in later by ModManager

    @property
    def display_name(self) -> str:
        return self.name if self.has_manifest else f"{self.folder_name} (no manifest.json)"

    @property
    def nexus_url(self) -> Optional[str]:
        """
        UpdateKeys often look like "Nexus:2400" or "Nexus:2400@1.2.0".
        If we can find one, build a direct link to the mod's Nexus page.
        """
        for key in self.update_keys:
            match = re.match(r"(?i)nexus:(\d+)", key)
            if match:
                return f"https://www.nexusmods.com/stardewvalley/mods/{match.group(1)}"
        return None

    @property
    def status_text(self) -> str:
        if not self.has_manifest:
            return "Missing manifest"
        if self.parse_error:
            return "Manifest error"
        if self.missing_dependencies:
            return "Missing dependency"
        return "Enabled" if self.enabled else "Disabled"


def _read_manifest_text(manifest_path: Path) -> str:
    """
    manifest.json files in the wild are sometimes saved with a UTF-8 BOM,
    or contain // comments, both of which break strict json.loads. Strip
    both before parsing, same as SMAPI itself does internally.
    """
    raw = manifest_path.read_text(encoding="utf-8-sig")
    # Strip // line comments (but not inside strings is good-enough heuristic
    # for the vast majority of real-world manifests; SMAPI tolerates these).
    no_comments = re.sub(r"(?m)^\s*//.*$", "", raw)
    return no_comments


def parse_manifest(mod_folder: Path, current_folder_name: str) -> ModInfo:
    """Build a ModInfo from a mod's folder, reading manifest.json if present."""
    enabled = not current_folder_name.startswith(".")
    manifest_file = mod_folder / "manifest.json"

    if not manifest_file.exists():
        return ModInfo(
            folder_path=mod_folder,
            folder_name=current_folder_name,
            name=current_folder_name.lstrip("."),
            enabled=enabled,
            has_manifest=False,
        )

    try:
        data = json.loads(_read_manifest_text(manifest_file))
    except json.JSONDecodeError as exc:
        return ModInfo(
            folder_path=mod_folder,
            folder_name=current_folder_name,
            name=current_folder_name.lstrip("."),
            enabled=enabled,
            has_manifest=True,
            parse_error=f"Invalid JSON: {exc}",
        )

    deps = []
    for dep in data.get("Dependencies", []) or []:
        dep_id = dep.get("UniqueID", "")
        if dep_id:
            deps.append(Dependency(unique_id=dep_id, required=dep.get("IsRequired", True)))

    return ModInfo(
        folder_path=mod_folder,
        folder_name=current_folder_name,
        name=data.get("Name", current_folder_name),
        version=str(data.get("Version", "?")),
        author=data.get("Author", "?"),
        description=data.get("Description", ""),
        unique_id=data.get("UniqueID", ""),
        content_pack_for=(data.get("ContentPackFor") or {}).get("UniqueID"),
        dependencies=deps,
        update_keys=data.get("UpdateKeys", []) or [],
        enabled=enabled,
        has_manifest=True,
    )
