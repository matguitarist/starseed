#!/usr/bin/env python3
"""
Stardew Mod Manager — a lightweight macOS-native-feeling mod manager for
SMAPI mods, built because Nexus Mods' official app doesn't support macOS.

Usage:
    python3 main.py

See README.md for setup (venv, PySide6 install) on Apple Silicon.
"""

import sys

from PySide6.QtWidgets import QApplication

from main_window import MainWindow


def main() -> int:
    app = QApplication(sys.argv)
    app.setApplicationName("Stardew Mod Manager")
    window = MainWindow()
    window.show()
    return app.exec()


if __name__ == "__main__":
    sys.exit(main())
