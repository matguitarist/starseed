import Foundation
import Testing
import DownloadKit
@testable import ModManagerCore

@Suite struct SMAPIAutoInstallTests {
    @Test func picksThePlainInstallerZip() throws {
        let json = """
        {"id": 1, "tag_name": "4.5.2", "assets": [
          {"id": 10, "name": "SMAPI-4.5.2-installer-double-zipped.zip", "browser_download_url": "https://example.com/double.zip"},
          {"id": 11, "name": "SMAPI-4.5.2-installer.zip", "browser_download_url": "https://example.com/plain.zip"}
        ]}
        """
        let release = try SMAPIInstaller.installer(in: GitHubRelease.decode(Data(json.utf8)))
        #expect(release.version == SemanticVersion("4.5.2"))
        #expect(release.installerURL.absoluteString == "https://example.com/plain.zip")

        let noInstaller = GitHubRelease(id: 2, tag: "4.6.0", name: "4.6.0", assets: [
            GitHubRelease.Asset(id: 20, name: "SMAPI-4.6.0-installer-double-zipped.zip", url: URL(string: "https://example.com/double.zip")!, size: 1),
        ])
        #expect(throws: ModManagerError.self) { try SMAPIInstaller.installer(in: noInstaller) }
    }

    @Test func readsTheInstallersOutcome() throws {
        try SMAPIInstaller.checkResult("Adding bundled mods...\n\nSMAPI is installed! Launch the game the same way as before to play with mods.")
        #expect(throws: ModManagerError.self) {
            try SMAPIInstaller.checkResult("----\nOops! Couldn't find the game folder.\n----\n")
        }
    }

    @Test func detectsALauncherReplacedByAGameUpdate() throws {
        let tmp = try TempDir()
        let launcher = tmp.url.appending(path: "StardewValley")
        try Data("#!/usr/bin/env bash\nexec ./StardewModdingAPI \"$@\"".utf8).write(to: launcher)
        let smapi = SMAPIInstallation(gameFolder: tmp.url, version: nil, gameVersion: nil)
        #expect(smapi.isLauncherHooked)
        try Data("#!/bin/sh\nexec \"./Stardew Valley\"".utf8).write(to: launcher)
        #expect(!smapi.isLauncherHooked)
    }
}

/// Installs SMAPI for real into a copy of the game folder:
/// SMAPI_INSTALL_TEST=/path/to/copy/Contents/MacOS swift test --filter LiveSMAPIInstall
@Suite(.enabled(if: ProcessInfo.processInfo.environment["SMAPI_INSTALL_TEST"] != nil))
struct LiveSMAPIInstallTests {
    @Test func installsTheLatestSMAPI() async throws {
        let folder = URL(filePath: ProcessInfo.processInfo.environment["SMAPI_INSTALL_TEST"]!, directoryHint: .isDirectory)
        let release = try await SMAPIInstaller.latestRelease()
        try await SMAPIInstaller.install(release, gameFolder: folder) { _ in }
        let installed = try #require(SMAPIInstallation.detect(modsURL: folder.appending(path: "Mods")))
        #expect(installed.version == release.version)
        #expect(installed.isLauncherHooked)
    }
}
