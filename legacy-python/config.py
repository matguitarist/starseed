"""
config.py
---------
Handles persistent app settings (where your Stardew "Mods" folder lives,
which Steam app ID to launch, etc). Settings live in:

    ~/Library/Application Support/StardewModManager/config.json

This is the standard place for a macOS app's own data, separate from the
game itself, so re-installing/clearing the game never touches your config.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Optional

APP_NAME = "StardewModManager"

# Default Steam install location for Stardew Valley on macOS.
# Confirmed against SMAPI's own log output ("Mods go here: ...") across
# multiple current reports, so this is a safe first guess to offer the user.
DEFAULT_MAC_STEAM_MODS_PATH = (
    Path.home()
    / "Library"
    / "Application Support"
    / "Steam"
    / "steamapps"
    / "common"
    / "Stardew Valley"
    / "Contents"
    / "MacOS"
    / "Mods"
)

STEAM_APP_ID = "413150"  # Stardew Valley's Steam AppID, used for the launch button


def app_support_dir() -> Path:
    """Directory where this app stores its own config/profile data."""
    d = Path.home() / "Library" / "Application Support" / APP_NAME
    d.mkdir(parents=True, exist_ok=True)
    return d


def config_path() -> Path:
    return app_support_dir() / "config.json"


def profiles_path() -> Path:
    return app_support_dir() / "profiles.json"


def load_config() -> dict[str, Any]:
    """Load saved settings, falling back to sane defaults if missing/corrupt."""
    path = config_path()
    if path.exists():
        try:
            return json.loads(path.read_text())
        except (json.JSONDecodeError, OSError):
            pass  # fall through to defaults if the file is missing/garbled
    return {"mods_path": None}


def save_config(data: dict[str, Any]) -> None:
    config_path().write_text(json.dumps(data, indent=2))


def get_mods_path() -> Optional[Path]:
    """Return the configured Mods folder, or None if never set."""
    raw = load_config().get("mods_path")
    return Path(raw) if raw else None


def set_mods_path(path: Path) -> None:
    cfg = load_config()
    cfg["mods_path"] = str(path)
    save_config(cfg)


def load_profiles() -> dict[str, list[str]]:
    """
    Profiles map a profile name -> list of mod unique IDs that should be
    ENABLED when that profile is applied. Anything not listed gets disabled.
    """
    path = profiles_path()
    if path.exists():
        try:
            return json.loads(path.read_text())
        except (json.JSONDecodeError, OSError):
            pass
    return {}


def save_profiles(profiles: dict[str, list[str]]) -> None:
    profiles_path().write_text(json.dumps(profiles, indent=2))
