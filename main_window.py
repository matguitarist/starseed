"""
main_window.py
---------------
The PySide6 GUI. Kept deliberately un-fancy: a checkbox list on the left
(checked = enabled), a detail pane on the right, and a toolbar for the
handful of actions you actually need — install, refresh, open folder,
launch game, profiles, change Mods path.
"""

from __future__ import annotations

from pathlib import Path

from PySide6.QtCore import Qt
from PySide6.QtGui import QAction, QColor, QPainter, QPixmap
from PySide6.QtWidgets import (
    QAbstractItemView,
    QDialog,
    QDialogButtonBox,
    QFileDialog,
    QHBoxLayout,
    QInputDialog,
    QLabel,
    QLineEdit,
    QListWidget,
    QListWidgetItem,
    QMainWindow,
    QMessageBox,
    QPushButton,
    QSplitter,
    QStatusBar,
    QTextBrowser,
    QToolBar,
    QVBoxLayout,
    QWidget,
)

import config
from mod_manager import ModManager, ModManagerError
from models import ModInfo

STATUS_COLORS = {
    "Enabled": QColor("#3ddc84"),
    "Disabled": QColor("#888888"),
    "Missing dependency": QColor("#e0a030"),
    "Missing manifest": QColor("#e05050"),
    "Manifest error": QColor("#e05050"),
}


def dot_icon(color: QColor, size: int = 14) -> QPixmap:
    """Small filled circle used as a status indicator next to each mod."""
    pixmap = QPixmap(size, size)
    pixmap.fill(Qt.transparent)
    painter = QPainter(pixmap)
    painter.setRenderHint(QPainter.Antialiasing)
    painter.setBrush(color)
    painter.setPen(Qt.NoPen)
    painter.drawEllipse(1, 1, size - 2, size - 2)
    painter.end()
    return pixmap


class ProfilesDialog(QDialog):
    """Save/apply/delete named sets of 'which mods are enabled'."""

    def __init__(self, parent: "MainWindow"):
        super().__init__(parent)
        self.main_window = parent
        self.setWindowTitle("Mod Profiles")
        self.resize(320, 280)

        self.list = QListWidget()
        self.list.addItems(sorted(config.load_profiles().keys()))

        save_btn = QPushButton("Save Current as New Profile…")
        apply_btn = QPushButton("Apply Selected")
        delete_btn = QPushButton("Delete Selected")
        close_btn = QDialogButtonBox(QDialogButtonBox.Close)

        save_btn.clicked.connect(self._save_profile)
        apply_btn.clicked.connect(self._apply_profile)
        delete_btn.clicked.connect(self._delete_profile)
        close_btn.rejected.connect(self.reject)
        close_btn.accepted.connect(self.accept)

        layout = QVBoxLayout(self)
        layout.addWidget(QLabel("A profile remembers which mods are enabled."))
        layout.addWidget(self.list)
        layout.addWidget(save_btn)
        layout.addWidget(apply_btn)
        layout.addWidget(delete_btn)
        layout.addWidget(close_btn)

    def _save_profile(self) -> None:
        name, ok = QInputDialog.getText(self, "Save Profile", "Profile name:")
        if not ok or not name.strip():
            return
        name = name.strip()
        enabled_ids = [
            m.unique_id for m in self.main_window.current_mods if m.enabled and m.unique_id
        ]
        profiles = config.load_profiles()
        profiles[name] = enabled_ids
        config.save_profiles(profiles)
        if not self.list.findItems(name, Qt.MatchExactly):
            self.list.addItem(name)
        QMessageBox.information(self, "Saved", f"Saved profile '{name}' ({len(enabled_ids)} mods enabled).")

    def _apply_profile(self) -> None:
        item = self.list.currentItem()
        if not item:
            return
        name = item.text()
        wanted_ids = set(config.load_profiles().get(name, []))
        self.main_window.apply_enabled_set(wanted_ids)
        QMessageBox.information(self, "Applied", f"Applied profile '{name}'.")

    def _delete_profile(self) -> None:
        item = self.list.currentItem()
        if not item:
            return
        name = item.text()
        profiles = config.load_profiles()
        profiles.pop(name, None)
        config.save_profiles(profiles)
        self.list.takeItem(self.list.row(item))


class MainWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("Stardew Mod Manager")
        self.resize(900, 600)
        self.setAcceptDrops(True)

        self.manager: ModManager | None = None
        self.current_mods: list[ModInfo] = []

        self._build_ui()
        self._restore_or_prompt_mods_path()

    # ------------------------------------------------------------------ #
    # UI construction
    # ------------------------------------------------------------------ #

    def _build_ui(self) -> None:
        toolbar = QToolBar("Main")
        toolbar.setMovable(False)
        self.addToolBar(toolbar)

        install_action = QAction("Install Mod(s)…", self)
        install_action.triggered.connect(self.install_mods_dialog)
        toolbar.addAction(install_action)

        refresh_action = QAction("Refresh", self)
        refresh_action.triggered.connect(self.refresh)
        toolbar.addAction(refresh_action)

        folder_action = QAction("Open Mods Folder", self)
        folder_action.triggered.connect(lambda: self.manager and self.manager.open_in_finder())
        toolbar.addAction(folder_action)

        toolbar.addSeparator()

        profiles_action = QAction("Profiles…", self)
        profiles_action.triggered.connect(self.open_profiles_dialog)
        toolbar.addAction(profiles_action)

        launch_action = QAction("Launch via Steam", self)
        launch_action.triggered.connect(lambda: ModManager.launch_via_steam(config.STEAM_APP_ID))
        toolbar.addAction(launch_action)

        toolbar.addSeparator()

        settings_action = QAction("Change Mods Folder…", self)
        settings_action.triggered.connect(self.change_mods_path_dialog)
        toolbar.addAction(settings_action)

        # --- central layout: search + list on the left, details on the right ---
        self.search_box = QLineEdit()
        self.search_box.setPlaceholderText("Filter by name, author, or ID…")
        self.search_box.textChanged.connect(self.refresh_list_view)

        self.list_widget = QListWidget()
        self.list_widget.setSelectionMode(QAbstractItemView.SingleSelection)
        self.list_widget.itemChanged.connect(self._on_item_check_changed)
        self.list_widget.currentItemChanged.connect(self._on_selection_changed)

        left_panel = QWidget()
        left_layout = QVBoxLayout(left_panel)
        left_layout.setContentsMargins(0, 0, 0, 0)
        left_layout.addWidget(self.search_box)
        left_layout.addWidget(self.list_widget)

        self.detail_title = QLabel("Select a mod")
        self.detail_title.setStyleSheet("font-size: 16px; font-weight: 600;")
        self.detail_meta = QLabel("")
        self.detail_meta.setWordWrap(True)
        self.detail_body = QTextBrowser()
        self.detail_body.setOpenExternalLinks(True)

        open_folder_btn = QPushButton("Open Mod Folder")
        open_folder_btn.clicked.connect(self._open_selected_folder)
        nexus_btn = QPushButton("Open Nexus Page")
        nexus_btn.clicked.connect(self._open_selected_nexus_page)
        delete_btn = QPushButton("Delete Mod")
        delete_btn.setStyleSheet("color: #e05050;")
        delete_btn.clicked.connect(self._delete_selected_mod)

        self.open_folder_btn = open_folder_btn
        self.nexus_btn = nexus_btn
        self.delete_btn = delete_btn

        btn_row = QHBoxLayout()
        btn_row.addWidget(open_folder_btn)
        btn_row.addWidget(nexus_btn)
        btn_row.addWidget(delete_btn)

        right_panel = QWidget()
        right_layout = QVBoxLayout(right_panel)
        right_layout.addWidget(self.detail_title)
        right_layout.addWidget(self.detail_meta)
        right_layout.addWidget(self.detail_body)
        right_layout.addLayout(btn_row)

        splitter = QSplitter()
        splitter.addWidget(left_panel)
        splitter.addWidget(right_panel)
        splitter.setStretchFactor(0, 2)
        splitter.setStretchFactor(1, 3)
        self.setCentralWidget(splitter)

        self.setStatusBar(QStatusBar())
        self._set_detail_buttons_enabled(False)

    def _set_detail_buttons_enabled(self, enabled: bool) -> None:
        self.open_folder_btn.setEnabled(enabled)
        self.delete_btn.setEnabled(enabled)
        self.nexus_btn.setEnabled(enabled)

    # ------------------------------------------------------------------ #
    # Mods path setup
    # ------------------------------------------------------------------ #

    def _restore_or_prompt_mods_path(self) -> None:
        saved = config.get_mods_path()
        if saved and saved.exists():
            self.manager = ModManager(saved)
            self.refresh()
            return

        default = config.DEFAULT_MAC_STEAM_MODS_PATH
        if default.exists():
            choice = QMessageBox.question(
                self,
                "Mods Folder Found",
                f"Found a Stardew Valley Mods folder at:\n\n{default}\n\nUse this one?",
            )
            if choice == QMessageBox.Yes:
                config.set_mods_path(default)
                self.manager = ModManager(default)
                self.refresh()
                return

        self.change_mods_path_dialog()

    def change_mods_path_dialog(self) -> None:
        start_dir = str(Path.home())
        chosen = QFileDialog.getExistingDirectory(
            self, "Select your Stardew Valley 'Mods' folder", start_dir
        )
        if not chosen:
            return
        path = Path(chosen)
        config.set_mods_path(path)
        self.manager = ModManager(path)
        self.refresh()

    # ------------------------------------------------------------------ #
    # Scanning / list rendering
    # ------------------------------------------------------------------ #

    def refresh(self) -> None:
        if not self.manager:
            return
        try:
            self.current_mods = self.manager.scan()
        except ModManagerError as exc:
            QMessageBox.warning(self, "Couldn't read Mods folder", str(exc))
            self.current_mods = []
        self.refresh_list_view()

    def refresh_list_view(self) -> None:
        query = self.search_box.text().strip().lower()
        self.list_widget.blockSignals(True)  # avoid re-triggering toggle handler while rebuilding
        self.list_widget.clear()

        visible_count = 0
        enabled_count = 0
        for mod in self.current_mods:
            if mod.enabled:
                enabled_count += 1
            haystack = f"{mod.name} {mod.author} {mod.unique_id}".lower()
            if query and query not in haystack:
                continue
            visible_count += 1

            item = QListWidgetItem(f"{mod.display_name}  v{mod.version}")
            item.setFlags(item.flags() | Qt.ItemIsUserCheckable)
            item.setCheckState(Qt.Checked if mod.enabled else Qt.Unchecked)
            item.setIcon(dot_icon(STATUS_COLORS.get(mod.status_text, QColor("gray"))))
            item.setData(Qt.UserRole, mod)
            item.setToolTip(mod.status_text)
            self.list_widget.addItem(item)

        self.list_widget.blockSignals(False)
        self.statusBar().showMessage(
            f"{visible_count} shown / {len(self.current_mods)} total mods — {enabled_count} enabled"
        )
        self._set_detail_buttons_enabled(False)
        self.detail_title.setText("Select a mod")
        self.detail_meta.setText("")
        self.detail_body.setHtml("")

    # ------------------------------------------------------------------ #
    # Selection / details
    # ------------------------------------------------------------------ #

    def _selected_mod(self) -> ModInfo | None:
        item = self.list_widget.currentItem()
        return item.data(Qt.UserRole) if item else None

    def _on_selection_changed(self, current: QListWidgetItem, _previous) -> None:
        mod: ModInfo | None = current.data(Qt.UserRole) if current else None
        if not mod:
            self._set_detail_buttons_enabled(False)
            return

        self._set_detail_buttons_enabled(True)
        self.nexus_btn.setEnabled(mod.nexus_url is not None)

        self.detail_title.setText(mod.display_name)
        self.detail_meta.setText(
            f"<b>Author:</b> {mod.author} &nbsp;&nbsp; "
            f"<b>Version:</b> {mod.version} &nbsp;&nbsp; "
            f"<b>Status:</b> {mod.status_text}"
        )

        body_parts = []
        if mod.parse_error:
            body_parts.append(f"<p style='color:#e05050'><b>{mod.parse_error}</b></p>")
        if mod.missing_dependencies:
            missing = ", ".join(mod.missing_dependencies)
            body_parts.append(
                f"<p style='color:#e0a030'><b>Missing/disabled dependencies:</b> {missing}</p>"
            )
        if mod.content_pack_for:
            body_parts.append(f"<p><b>Content pack for:</b> {mod.content_pack_for}</p>")
        if mod.unique_id:
            body_parts.append(f"<p><b>Unique ID:</b> {mod.unique_id}</p>")
        if mod.description:
            body_parts.append(f"<p>{mod.description}</p>")
        body_parts.append(f"<p style='color:gray'><b>Folder:</b> {mod.folder_path}</p>")

        self.detail_body.setHtml("".join(body_parts))

    def _on_item_check_changed(self, item: QListWidgetItem) -> None:
        mod: ModInfo = item.data(Qt.UserRole)
        if not mod or not self.manager:
            return
        wants_enabled = item.checkState() == Qt.Checked
        if wants_enabled == mod.enabled:
            return
        try:
            self.manager.set_enabled(mod, wants_enabled)
        except ModManagerError as exc:
            QMessageBox.warning(self, "Couldn't toggle mod", str(exc))
        self.refresh()

    def apply_enabled_set(self, wanted_unique_ids: set[str]) -> None:
        """Used by Profiles: enable exactly the given mods, disable everything else."""
        if not self.manager:
            return
        for mod in self.current_mods:
            should_be_enabled = mod.unique_id in wanted_unique_ids
            if should_be_enabled != mod.enabled:
                try:
                    self.manager.set_enabled(mod, should_be_enabled)
                except ModManagerError:
                    pass  # best-effort; a name collision here shouldn't block the whole apply
        self.refresh()

    # ------------------------------------------------------------------ #
    # Detail panel button actions
    # ------------------------------------------------------------------ #

    def _open_selected_folder(self) -> None:
        mod = self._selected_mod()
        if mod and self.manager:
            self.manager.open_in_finder(mod.folder_path)

    def _open_selected_nexus_page(self) -> None:
        mod = self._selected_mod()
        if mod and mod.nexus_url:
            import webbrowser

            webbrowser.open(mod.nexus_url)

    def _delete_selected_mod(self) -> None:
        mod = self._selected_mod()
        if not mod or not self.manager:
            return
        choice = QMessageBox.question(
            self,
            "Delete Mod",
            f"Permanently delete '{mod.display_name}'?\nThis removes the folder and cannot be undone.",
        )
        if choice == QMessageBox.Yes:
            self.manager.delete_mod(mod)
            self.refresh()

    # ------------------------------------------------------------------ #
    # Installing mods
    # ------------------------------------------------------------------ #

    def install_mods_dialog(self) -> None:
        if not self.manager:
            return
        files, _ = QFileDialog.getOpenFileNames(
            self, "Select downloaded mod .zip file(s)", str(Path.home() / "Downloads"), "Zip files (*.zip)"
        )
        for f in files:
            self._install_one_zip(Path(f))
        self.refresh()

    def _install_one_zip(self, zip_path: Path) -> None:
        if not self.manager:
            return

        def ask_overwrite(name: str) -> bool:
            choice = QMessageBox.question(
                self,
                "Mod Already Installed",
                f"'{name}' is already in your Mods folder. Overwrite it with this version?",
            )
            return choice == QMessageBox.Yes

        result = self.manager.install_from_zip(zip_path, ask_overwrite)

        lines = []
        if result.installed:
            lines.append("Installed/updated: " + ", ".join(result.installed))
        if result.skipped:
            lines.append("Skipped: " + ", ".join(result.skipped))
        if result.errors:
            lines.append("Errors:\n" + "\n".join(result.errors))

        if result.errors:
            QMessageBox.warning(self, zip_path.name, "\n\n".join(lines) or "Nothing happened.")
        elif lines:
            QMessageBox.information(self, zip_path.name, "\n\n".join(lines))

    def open_profiles_dialog(self) -> None:
        ProfilesDialog(self).exec()

    # ------------------------------------------------------------------ #
    # Drag & drop zip installation
    # ------------------------------------------------------------------ #

    def dragEnterEvent(self, event) -> None:
        if event.mimeData().hasUrls():
            event.acceptProposedAction()

    def dropEvent(self, event) -> None:
        if not self.manager:
            return
        for url in event.mimeData().urls():
            path = Path(url.toLocalFile())
            if path.suffix.lower() == ".zip":
                self._install_one_zip(path)
        self.refresh()
