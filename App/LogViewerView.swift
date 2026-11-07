import AppKit
import LogKitUI
import ModManagerCore
import os
import SwiftUI

// The SMAPI Log page: LogKit's viewer (levels, problems, search, Clear,
// follow live, copy and export) with what only Starseed knows: what to do
// about each insight, the save's missing content, the mods SMAPI loaded,
// and smapi.io.

extension LogViewerModel {
    /// SMAPI's latest and crash logs, and the earlier ones in its folder.
    static func smapi(names: DependencyNames) -> LogViewerModel {
        let model = LogViewerModel(file: LogFileSource(
            files: [.init(String(localized: "Latest Log"), url: SMAPILog.latestLogURL),
                    .init(String(localized: "Crash Log"), url: SMAPILog.crashLogURL)],
            folder: SMAPILog.defaultFolder,
            parser: SMAPILog.parser(describe: { SMAPIInsightText.describe($0, names: names) })))
        model.showInspector = UserDefaults.standard.object(forKey: "showLoadedMods") as? Bool ?? true
        return model
    }
}

/// Names of mods by UniqueID, from SMAPI's database, readable while the log
/// is parsed off the main thread.
final class DependencyNames: Sendable {
    private let names = OSAllocatedUnfairLock<[String: String]>(initialState: [:])

    func update(_ records: [String: SMAPIModRecord]) {
        let known = records.compactMapValues(\.name)
        names.withLock { $0 = known }
    }

    func name(for uniqueID: String) -> String? {
        names.withLock { $0[uniqueID.lowercased()] }
    }
}

struct LogViewerView: View {
    @AppModelEnvironment private var model
    /// What Starseed reads from the log shown, computed off the main thread
    /// once per change of the log (or of Clear).
    @State private var facts = SMAPILogFacts()

    var body: some View {
        let log = model.smapiLog
        LogViewer(model: log, options: options)
            .navigationTitle("SMAPI Log")
            .toolbar {
                ToolbarItem(placement: .primaryAction) { PlayToolbarButton() }
            }
            .task(id: documentKey) { await updateFacts() }
            .onChange(of: log.showInspector) { _, shown in
                UserDefaults.standard.set(shown, forKey: "showLoadedMods")
            }
    }

    private var options: LogViewerOptions {
        LogViewerOptions(
            emptyTitle: String(localized: "No SMAPI Log Yet"),
            emptyMessage: String(localized: "Launch the game through SMAPI once; its log appears here, updating live while you play."),
            emptyActions: { AnyView(Button("Launch Stardew Valley") { model.launchGame() }) },
            insightsTitle: String(localized: "What SMAPI is telling you"),
            insightActions: { insight in
                AnyView(InsightActions(insight: facts.insights.first { $0.id == insight.id },
                                       showSource: { model.smapiLog.filter.source = $0 }))
            },
            banner: { _ in AnyView(MissingContentBanner(facts: facts)) },
            headerAccessory: { AnyView(HeaderAccessory()) },
            inspectorTitle: String(localized: "Loaded Mods"),
            inspector: { _ in AnyView(LoadedModsInspector(loaded: facts.loadedMods)) },
            shareActions: [.init(String(localized: "Upload to smapi.io…")) { _ in uploadToSMAPI() }],
            sourceColor: { source in
                switch source {
                case "SMAPI": .blue
                case "game": .teal
                default: .indigo
                }
            })
    }

    /// Changes when the log shown changes: another file, a new session, new lines, Clear.
    private var documentKey: String {
        let log = model.smapiLog
        let entries = log.document?.entries
        return "\(log.fileURL?.path ?? "") \(entries?.first?.id ?? -1) \(entries?.count ?? -1) \(entries?.last?.id ?? -1)"
    }

    private func updateFacts() async {
        let log = model.smapiLog
        guard let entries = log.document?.entries else {
            facts = SMAPILogFacts()
            return
        }
        let updated = await Task.detached { SMAPILogFacts(log: SMAPILog(entries: entries)) }.value
        facts = updated
        // The Installed list warns about conflicts from the latest session.
        if log.fileURL == SMAPILog.latestLogURL, log.clearMark == nil {
            model.setLogConflicts(from: updated.insights)
        }
    }

    /// smapi.io's log parser reads SMAPI's own format: copy the file as is, then open the page.
    private func uploadToSMAPI() {
        guard let url = model.smapiLog.fileURL, let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        model.openInBrowser(URL(string: "https://smapi.io/log")!)
    }
}

/// Everything the page reads from the log besides what LogKit shows.
struct SMAPILogFacts: Sendable {
    var insights: [SMAPIInsight] = []
    var unknownLocations: [UnknownLocation] = []
    var loadedSaveID: String?
    var loadedMods: [LoadedMod] = []

    init() {}

    init(log: SMAPILog) {
        insights = log.insights
        unknownLocations = log.unknownLocations
        loadedSaveID = log.loadedSaveID
        loadedMods = log.loadedMods
    }
}

/// Where the game came from, and the profile in use, after SMAPI's versions.
private struct HeaderAccessory: View {
    @AppModelEnvironment private var model

    var body: some View {
        if let store = model.gameStore?.displayName {
            Label(store, systemImage: "bag").lineLimit(1)
        }
        ProfileIndicator()
    }
}

// MARK: Insights

/// "What SMAPI is telling you" in plain words: skipped mods, crashing mods,
/// updates and conflicts. Runs while the log is parsed, off the main thread.
enum SMAPIInsightText {
    nonisolated static func describe(_ insight: SMAPIInsight, names: DependencyNames) -> (title: String, detail: String) {
        (title(insight), detail(insight, names: names))
    }

    nonisolated private static func title(_ insight: SMAPIInsight) -> String {
        switch insight.kind {
        case .skippedMod(let name, _, let missing, let smapi):
            if !missing.isEmpty { return String(localized: "\(name) didn't load: it needs mods you don't have") }
            if smapi != nil { return String(localized: "\(name) didn't load: it needs a newer SMAPI") }
            return String(localized: "\(name) didn't load")
        case .modErrors(let source, let count, _):
            return count == 1 ? String(localized: "\(source) had an error while you played") : String(localized: "\(source) had \(count) errors while you played")
        case .updatesAvailable(let list):
            return list.count == 1 ? String(localized: "1 mod update available") : String(localized: "\(list.count) mod updates available")
        case .smapiUpdate(let version, _):
            return String(localized: "SMAPI \(version) is available")
        case .assetConflict(let mods, _):
            return String(localized: "Conflict: \(mods.formatted(.list(type: .and)))")
        }
    }

    nonisolated private static func detail(_ insight: SMAPIInsight, names: DependencyNames) -> String {
        switch insight.kind {
        case .skippedMod(_, let reason, let missing, let smapi):
            if !missing.isEmpty {
                let names = missing.map { names.name(for: $0) ?? $0 }
                return String(localized: "Missing: \(names.joined(separator: ", "))")
            }
            if let smapi, !smapi.isEmpty { return String(localized: "It needs SMAPI \(smapi) or later.") }
            return String(localized: "SMAPI says: \(reason).")
        case .modErrors(_, _, let events):
            let advice = String(localized: "It may be broken or outdated. Updating it often helps; if not, report it to its author with your log.")
            return events.isEmpty ? advice : advice + " " + String(localized: "(During: \(events.joined(separator: ", ")).)")
        case .updatesAvailable(let list):
            return list.map { "\($0.name) \($0.version)" }.joined(separator: ", ")
        case .smapiUpdate:
            return String(localized: "Newer SMAPI versions fix bugs and support newer mods.")
        case .assetConflict(_, let assets):
            return String(localized: "They replace the same game files (\(ConflictsSection.assetList(assets))), so SMAPI used the originals and neither change shows. Disable one of them.")
        }
    }
}

/// A way to fix each insight.
private struct InsightActions: View {
    @AppModelEnvironment private var model
    let insight: SMAPIInsight?
    let showSource: (String) -> Void

    var body: some View {
        switch insight?.kind {
        case .skippedMod(let name, _, let missing, let smapi)?:
            if !missing.isEmpty {
                Button("Install Missing") { model.installMissing(uniqueIDs: missing, neededBy: name) }
                    .task {
                        // Look up the missing mods' names, then show them instead of their IDs.
                        let unknown = missing.contains { model.record(forDependency: $0)?.name == nil }
                        await model.resolve(uniqueIDs: missing)
                        if unknown, missing.contains(where: { model.record(forDependency: $0)?.name != nil }) {
                            await model.smapiLog.reload()
                        }
                    }
            } else if smapi != nil {
                SMAPIInstallButton()
            } else if let mod = model.installedMod(named: name), let nexusID = model.nexusID(for: mod) {
                Button("Check for Update…") { model.nexusSheet = NexusSheetRequest(modID: nexusID) }
            }
        case .modErrors(let source, _, _)?:
            HStack {
                Button("Show Messages") { showSource(source) }
                if let mod = model.installedMod(named: source), let update = model.update(for: mod), let nexusID = model.nexusID(for: mod) {
                    Button("Update to \(update.version)") {
                        model.queueNexusInstalls([NexusInstallRequest(modID: nexusID, title: mod.displayName, version: update.version)])
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        case .updatesAvailable?:
            Button("Open Updates") { model.sidebarSelection = .updates }
        case .smapiUpdate?:
            SMAPIInstallButton()
        case .assetConflict(let mods, _)?:
            let installed = mods.compactMap { model.installedMod(named: $0) }.filter(\.isEnabled)
            if installed.count > 1 {
                Menu("Disable One") {
                    ForEach(installed) { mod in
                        Button(mod.displayName) {
                            model.setEnabled(Set((model.group(containing: mod)?.mods ?? [mod]).map(\.id)), false)
                        }
                    }
                }
                .fixedSize()
                .help("Disabling can be undone with ⌘Z")
            }
        case nil:
            EmptyView()
        }
    }
}

// MARK: Missing content

/// Shown when the session loaded a save whose mods aren't installed.
private struct MissingContentBanner: View {
    @AppModelEnvironment private var model
    let facts: SMAPILogFacts

    var body: some View {
        let unknown = facts.unknownLocations
        if !unknown.isEmpty, let saveID = facts.loadedSaveID {
            let npcCount = Set(unknown.flatMap(\.npcs)).count
            HStack(spacing: 10) {
                Image(systemName: "puzzlepiece.extension.fill")
                    .font(.title3)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 1) {
                    Text("This save uses mods you don't have").font(.headline)
                    let locations = String(localized: "\(unknown.count) locations")
                    let dropped = npcCount > 0 ? [locations, String(localized: "\(npcCount) NPCs")].formatted(.list(type: .and)) : locations
                    Text("The game dropped \(dropped) from “\(saveID)” because their mods aren't installed.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Find Missing Mods") { model.showSave(id: saveID) }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.orange.opacity(0.12))
            Divider()
        }
    }
}

// MARK: Loaded mods

/// The panel at the right of the SMAPI Log: what SMAPI actually loaded in
/// that session. Names jump to the mod in the Installed list; hovering one
/// shows its description.
private struct LoadedModsInspector: View {
    @AppModelEnvironment private var model
    let loaded: [LoadedMod]

    var body: some View {
        let mods = loaded.filter { !$0.isContentPack }
        let packs = loaded.filter(\.isContentPack)
        if loaded.isEmpty {
            ContentUnavailableView("No Loaded Mods Listed", systemImage: "checklist",
                                   description: Text("SMAPI lists the mods it loaded when the game starts."))
        } else {
            List {
                Section {
                    ForEach(mods) { row($0) }
                } header: {
                    Text("Mods (\(mods.count))")
                }
                if !packs.isEmpty {
                    Section {
                        ForEach(packs) { row($0) }
                    } header: {
                        Text("Content packs (\(packs.count))")
                    }
                }
            }
            .listStyle(.sidebar)
            .safeAreaInset(edge: .top, spacing: 0) {
                Label(packs.isEmpty ? String(localized: "Loaded \(mods.count) mods")
                      : String(localized: "Loaded \(mods.count) mods") + " · " + String(localized: "\(packs.count) content packs"),
                      systemImage: "checklist")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.bar)
                    .overlay(alignment: .bottom) { Divider() }
            }
        }
    }

    private func row(_ item: LoadedMod) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).imageScale(.small)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    if let installed = model.installedMod(named: item.name) {
                        Button(item.name) {
                            model.reveal(rowID: model.group(containing: installed)?.id ?? installed.id)
                        }
                        .buttonStyle(.link)
                        .help("Show \(item.name) in the list")
                    } else {
                        Text(item.name)
                    }
                    Text(verbatim: item.version).monospacedDigit().foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    if let author = item.author {
                        Text("by \(author)")
                    }
                    if let framework = item.contentPackFor, !framework.isEmpty {
                        Text("· for \(framework)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        .help(item.description ?? "")
    }
}
