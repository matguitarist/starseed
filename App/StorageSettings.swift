// Settings → Storage: what the Mods folder, kept versions and save backups
// take on disk, with ways to clean up. Everything removed goes to the Trash.

import AppKit
import ModManagerCore
import SwiftUI

struct StorageReport: Sendable {
    struct ModSize: Sendable, Identifiable {
        let id: String
        let name: String
        let bytes: Int64
    }
    struct KeptVersion: Sendable, Identifiable {
        let version: ArchivedVersion
        let name: String
        let bytes: Int64
        var id: URL { version.id }
    }

    var modsTotal: Int64 = 0
    var largestMods: [ModSize] = []
    var kept: [KeptVersion] = []
    var backups: [SaveBackup] = []

    var keptTotal: Int64 { kept.reduce(0) { $0 + $1.bytes } }
    var backupsTotal: Int64 { backups.reduce(0) { $0 + $1.byteCount } }
}

extension AppModel {
    func storageReport() async -> StorageReport {
        // Whole mods, as the Installed list shows them (not their parts).
        let groups = allGroups.map { (id: $0.id, name: $0.name, folders: $0.mods.map(\.folderURL)) }
        let mods = mods.map { (uniqueID: $0.uniqueID.lowercased(), name: group(containing: $0)?.name ?? $0.displayName) }
        let modsURL = manager?.modsURL
        let archive = modArchive
        let backups = await backupStore.list().filter { !$0.isSMAPIBackup }
        return await Task.detached {
            var report = StorageReport()
            report.modsTotal = modsURL.map(DiskUsage.size(of:)) ?? 0
            report.largestMods = groups.map { group in
                StorageReport.ModSize(id: group.id, name: group.name, bytes: group.folders.reduce(0) { $0 + DiskUsage.size(of: $1) })
            }
            .sorted { $0.bytes > $1.bytes }
            let names = Dictionary(mods.map { ($0.uniqueID, $0.name) }, uniquingKeysWith: { first, _ in first })
            report.kept = archive.allVersions().map { version in
                let name = names[version.uniqueID.lowercased()] ?? version.folder.lastPathComponent
                return StorageReport.KeptVersion(version: version, name: name, bytes: DiskUsage.size(of: version.folder.deletingLastPathComponent()))
            }
            report.backups = backups
            return report
        }.value
    }

    func removeKeptVersions(_ versions: [ArchivedVersion]) {
        var failures: [String] = []
        for version in versions {
            do { try modArchive.remove(version) } catch { failures.append(error.localizedDescription) }
        }
        if !failures.isEmpty { show("Couldn't Remove Some Files", detail: failures.joined(separator: "\n")) }
    }

    func removeBackups(_ backups: [SaveBackup]) {
        var failures: [String] = []
        for backup in backups {
            do { try backupStore.delete(backup) } catch { failures.append(error.localizedDescription) }
        }
        if !failures.isEmpty { show("Couldn't Remove Some Files", detail: failures.joined(separator: "\n")) }
    }
}

struct StorageSettings: View {
    @AppModelEnvironment private var model
    @State private var report: StorageReport?
    @State private var showAllMods = false
    @State private var confirmKept = false
    @State private var confirmBackups = false

    private static let oldBackupAge: TimeInterval = 30 * 24 * 60 * 60

    var body: some View {
        Form {
            if let report {
                Section {
                    LabeledContent("Mods folder", value: Self.bytes(report.modsTotal))
                    ForEach(showAllMods ? report.largestMods : Array(report.largestMods.prefix(5))) { mod in
                        LabeledContent(mod.name, value: Self.bytes(mod.bytes))
                            .font(.callout)
                    }
                    if report.largestMods.count > 5 {
                        Button(showAllMods ? String(localized: "Show Fewer") : String(localized: "Show All \(report.largestMods.count)")) { showAllMods.toggle() }
                            .buttonStyle(.link)
                    }
                } header: {
                    Text("Mods")
                } footer: {
                    Text("Largest first. Remove mods you don't use from the Installed list.")
                }

                Section {
                    LabeledContent("Kept versions", value: report.kept.isEmpty ? String(localized: "None") : "\(report.kept.count) · \(Self.bytes(report.keptTotal))")
                    ForEach(report.kept.prefix(8)) { kept in
                        LabeledContent {
                            HStack {
                                Text(Self.bytes(kept.bytes)).foregroundStyle(.secondary)
                                Button {
                                    model.removeKeptVersions([kept.version])
                                    Task { await reload() }
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .help("Move this version to the Trash")
                            }
                        } label: {
                            Text(verbatim: "\(kept.name) \(kept.version.version)")
                            Text(kept.version.date.formatted(date: .abbreviated, time: .omitted))
                        }
                        .font(.callout)
                    }
                    HStack {
                        Button("Show in Finder") { NSWorkspace.shared.open(model.modArchive.directory) }
                        Spacer()
                        Button("Remove All…", role: .destructive) { confirmKept = true }
                            .disabled(report.kept.isEmpty)
                    }
                } header: {
                    Text("Previous versions of mods")
                } footer: {
                    Text("Kept when a mod is updated, so it can be rolled back (Previous Versions in the details panel). The last 3 of each mod are kept.")
                }

                Section {
                    let old = report.backups.filter { $0.date < Date(timeIntervalSinceNow: -Self.oldBackupAge) }
                    LabeledContent("Backups", value: report.backups.isEmpty ? String(localized: "None") : "\(report.backups.count) · \(Self.bytes(report.backupsTotal))")
                    if !old.isEmpty {
                        LabeledContent("Older than 30 days", value: "\(old.count) · \(Self.bytes(old.reduce(0) { $0 + $1.byteCount }))")
                    }
                    HStack {
                        Button("Show in Finder") { NSWorkspace.shared.open(model.backupStore.directory) }
                        Spacer()
                        Button("Remove Older Than 30 Days…", role: .destructive) { confirmBackups = true }
                            .disabled(old.isEmpty)
                    }
                } header: {
                    Text("Save backups")
                } footer: {
                    Text("Starseed's own backups (SMAPI's daily backups aren't touched). Restore them from Saves.")
                }
            } else {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Measuring…").foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .task { await reload() }
        .confirmationDialog("Remove all previous versions?", isPresented: $confirmKept, titleVisibility: .visible) {
            Button("Move to Trash", role: .destructive) {
                model.removeKeptVersions(report?.kept.map(\.version) ?? [])
                Task { await reload() }
            }
        } message: {
            Text("Mods can't be rolled back to these versions afterwards, unless you put them back from the Trash.")
        }
        .confirmationDialog("Remove backups older than 30 days?", isPresented: $confirmBackups, titleVisibility: .visible) {
            Button("Move to Trash", role: .destructive) {
                model.removeBackups(report?.backups.filter { $0.date < Date(timeIntervalSinceNow: -Self.oldBackupAge) } ?? [])
                Task { await reload() }
            }
        } message: {
            Text("They go to the Trash, so you can still get them back from Finder.")
        }
    }

    private func reload() async {
        report = await model.storageReport()
    }

    static func bytes(_ count: Int64) -> String {
        count.formatted(.byteCount(style: .file))
    }
}

/// "12.4 MB" for a mod, measured off the main thread.
struct ModSizeText: View {
    let folder: URL
    @State private var bytes: Int64?

    var body: some View {
        Text(bytes.map(StorageSettings.bytes) ?? "…")
            .task(id: folder) {
                let folder = folder
                bytes = await Task.detached { DiskUsage.size(of: folder) }.value
            }
    }
}
