import AppKit
import ModManagerCore
import SwiftUI

extension LogLevel {
    /// Colors follow SMAPI's console: dim trace/debug, plain info, yellow
    /// warnings, red errors, magenta alerts.
    var color: Color {
        switch self {
        case .trace: .gray
        case .debug: .secondary
        case .info: .primary
        case .warn: .orange
        case .error: .red
        case .alert: .purple
        }
    }

    var symbol: String {
        switch self {
        case .trace: "ellipsis.circle"
        case .debug: "ladybug"
        case .info: "info.circle"
        case .warn: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        case .alert: "bell.fill"
        }
    }
}

/// SMAPI's console log with colored levels, filters, search and a
/// per-mod problem summary. Reloads automatically while the game runs.
struct LogViewerView: View {
    @Environment(AppModel.self) private var model

    @State private var fileURL = SMAPILog.latestLogURL
    @State private var log: SMAPILog?
    @State private var loadError: String?
    @State private var lastModified: Date?
    @State private var levels: Set<LogLevel> = [.debug, .info, .warn, .error, .alert]
    @State private var sourceFilter: String?
    @State private var searchText = ""
    @State private var followLive = true

    /// The log minus anything before "Clear" (if cleared in this session).
    private var visibleLog: SMAPILog? {
        guard let log else { return nil }
        guard let mark = activeClearMark(for: log) else { return log }
        return log.droppingFirst(mark.entryCount)
    }

    private func activeClearMark(for log: SMAPILog) -> AppModel.LogClearMark? {
        guard let mark = model.logClearMark, mark.file == fileURL, mark.session == log.sessionKey,
              mark.entryCount <= log.entries.count
        else { return nil }
        return mark
    }

    var body: some View {
        Group {
            if let log = visibleLog {
                VStack(spacing: 0) {
                    missingContentBanner(log)
                    InsightsPanel(insights: log.insights, onShowSource: { sourceFilter = $0 })
                    summaryHeader(log)
                    Divider()
                    entryList(log)
                }
            } else {
                ContentUnavailableView {
                    Label("No SMAPI Log Yet", systemImage: "doc.text.magnifyingglass")
                } description: {
                    Text(loadError ?? "Launch the game through SMAPI once; its log appears here, updating live while you play.")
                } actions: {
                    Button("Launch Stardew Valley") { model.launchGame() }
                    Button("Open Log File…", action: chooseFile)
                }
            }
        }
        .navigationTitle("SMAPI Log")
        .navigationSubtitle(fileURL.lastPathComponent)
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search log")
        .toolbar { toolbar }
        .task(id: fileURL) {
            reload(force: true)
            // Poll for changes so the log follows a running game.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                if followLive { reload(force: false) }
            }
        }
    }

    // MARK: Missing content

    /// Shown when the session loaded a save whose mods aren't installed.
    @ViewBuilder
    private func missingContentBanner(_ log: SMAPILog) -> some View {
        let unknown = log.unknownLocations
        if !unknown.isEmpty, let saveID = log.loadedSaveID {
            let npcCount = Set(unknown.flatMap(\.npcs)).count
            HStack(spacing: 10) {
                Image(systemName: "puzzlepiece.extension.fill")
                    .font(.title3)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 1) {
                    Text("This save uses mods you don't have").font(.headline)
                    Text("The game dropped \(unknown.count) locations\(npcCount > 0 ? " and \(npcCount) NPCs" : "") from “\(saveID)” because their mods aren't installed.")
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

    // MARK: Header

    private func summaryHeader(_ log: SMAPILog) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                if let smapi = log.smapiVersion {
                    Label("SMAPI \(smapi)", systemImage: "gearshape.2")
                }
                if let game = log.gameVersion {
                    Label("Stardew Valley \(game)", systemImage: "leaf")
                }
                if let platform = log.platform {
                    Label(platform, systemImage: "desktopcomputer").lineLimit(1)
                }
                Spacer()
                if let full = self.log, let mark = activeClearMark(for: full) {
                    Text("Cleared at \(mark.date.formatted(date: .omitted, time: .standard)) · \(mark.entryCount) earlier messages hidden")
                        .foregroundStyle(.secondary)
                    Button("Show All") { model.logClearMark = nil }
                        .controlSize(.small)
                } else if let lastModified {
                    Text("Updated \(lastModified.formatted(date: .omitted, time: .standard))")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.callout)

            // Level toggles double as counts.
            HStack(spacing: 6) {
                ForEach(LogLevel.allCases, id: \.self) { level in
                    levelChip(level, count: log.count(of: level))
                }
                Spacer()
                if let sourceFilter {
                    Button {
                        self.sourceFilter = nil
                    } label: {
                        Label("Source: \(sourceFilter)", systemImage: "xmark.circle.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            let problems = log.problemsBySource
            if !problems.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        Text("Problems:").font(.callout.bold()).foregroundStyle(.secondary)
                        ForEach(problems, id: \.source) { problem in
                            Button {
                                sourceFilter = sourceFilter == problem.source ? nil : problem.source
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: problem.worst.symbol)
                                    Text("\(problem.source) (\(problem.count))")
                                }
                                .font(.callout)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 5)
                                .background(problem.worst.color.opacity(sourceFilter == problem.source ? 0.35 : 0.15), in: Capsule())
                                .foregroundStyle(problem.worst.color)
                            }
                            .buttonStyle(.plain)
                            .help("Show only \(problem.source)")
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func levelChip(_ level: LogLevel, count: Int) -> some View {
        let isOn = levels.contains(level)
        return Button {
            if isOn { levels.remove(level) } else { levels.insert(level) }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: level.symbol)
                Text("\(level.title) \(count)")
                    .monospacedDigit()
            }
            .font(.callout.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(isOn ? level.color.opacity(0.2) : Color.clear, in: Capsule())
            .overlay(Capsule().strokeBorder(level.color.opacity(isOn ? 0.6 : 0.25)))
            .foregroundStyle(isOn ? level.color : .secondary)
        }
        .buttonStyle(.plain)
        .help(isOn ? "Hide \(level.title.lowercased()) messages" : "Show \(level.title.lowercased()) messages")
    }

    // MARK: Entries

    private func filteredEntries(_ log: SMAPILog) -> [LogEntry] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return log.entries.filter { entry in
            levels.contains(entry.level)
                && (sourceFilter == nil || entry.source == sourceFilter)
                && (query.isEmpty || entry.message.localizedCaseInsensitiveContains(query) || entry.source.localizedCaseInsensitiveContains(query))
        }
    }

    private func entryList(_ log: SMAPILog) -> some View {
        let entries = filteredEntries(log)
        return ScrollViewReader { proxy in
            List(entries) { entry in
                LogRow(entry: entry, onSourceTap: { sourceFilter = $0 })
                    .listRowBackground(entry.isProblem ? entry.level.color.opacity(0.08) : Color.clear)
                    .id(entry.id)
            }
            .listStyle(.plain)
            .overlay {
                if entries.isEmpty {
                    if log.entries.isEmpty, model.logClearMark != nil {
                        ContentUnavailableView(
                            "Log Cleared",
                            systemImage: "clear",
                            description: Text("New messages appear here as SMAPI writes them. Starting the game again begins a fresh log.")
                        )
                    } else {
                        ContentUnavailableView("No Matching Messages", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .onChange(of: log.entries.count) {
                if followLive, let last = entries.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                Button("Latest Log") { fileURL = SMAPILog.latestLogURL }
                Button("Crash Log") { fileURL = SMAPILog.crashLogURL }
                    .disabled(!FileManager.default.fileExists(atPath: SMAPILog.crashLogURL.path(percentEncoded: false)))
                Divider()
                Button("Open Log File…", action: chooseFile)
            } label: {
                Label("Log File", systemImage: "doc.text")
            }
            .help("Choose which log to show")

            Toggle(isOn: $followLive) {
                Label("Follow Live", systemImage: "dot.radiowaves.left.and.right")
            }
            .help("Reload automatically and scroll to new messages while the game runs")

            Button {
                if let log { model.logClearMark = AppModel.LogClearMark(file: fileURL, session: log.sessionKey ?? "", entryCount: log.entries.count, date: .now) }
            } label: {
                Label("Clear", systemImage: "clear")
            }
            .keyboardShortcut("k")
            .help("Clear: hide everything logged so far and show only new messages (⌘K). The log file isn't changed.")
            .disabled(log == nil)

            Button {
                reload(force: true)
            } label: {
                Label("Reload", systemImage: "arrow.clockwise")
            }

            Menu {
                Button("Copy Log") { copyLog() }
                Button("Upload to smapi.io…") {
                    // smapi.io's log parser takes a pasted log; copy it and open the page.
                    copyLog()
                    model.openInBrowser(URL(string: "https://smapi.io/log")!)
                }
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([fileURL]) }
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .disabled(log == nil)
            .help("Copy, share, or show the log file")
        }
    }

    // MARK: Loading

    private func reload(force: Bool) {
        let path = fileURL.path(percentEncoded: false)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else {
            log = nil
            loadError = nil
            return
        }
        let modified = attributes[.modificationDate] as? Date
        guard force || modified != lastModified else { return }
        do {
            log = try SMAPILog.load(from: fileURL)
            lastModified = modified
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .log]
        panel.directoryURL = SMAPILog.defaultFolder
        panel.showsHiddenFiles = true
        if panel.runModal() == .OK, let url = panel.url {
            fileURL = url
        }
    }

    private func copyLog() {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

private struct LogRow: View {
    let entry: LogEntry
    let onSourceTap: (String) -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(entry.time)
                .foregroundStyle(.tertiary)
            Text(entry.level.rawValue)
                .font(.system(.caption, design: .monospaced).weight(.bold))
                .foregroundStyle(entry.level == .info ? Color.secondary : entry.level.color)
                .frame(width: 44, alignment: .leading)
            Button(entry.source) { onSourceTap(entry.source) }
                .buttonStyle(.plain)
                .foregroundStyle(sourceColor)
                .fontWeight(.semibold)
                .lineLimit(1)
                .frame(width: 140, alignment: .leading)
                .help("Show only \(entry.source)")
            Text(entry.message)
                .foregroundStyle(entry.level.color)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(.callout, design: .monospaced))
        .padding(.vertical, 1)
    }

    private var sourceColor: Color {
        switch entry.source {
        case "SMAPI": .blue
        case "game": .teal
        default: .indigo
        }
    }
}

/// "What SMAPI is telling you": skipped mods, crashing mods and updates in
/// plain words, each with a way to fix it.
private struct InsightsPanel: View {
    @Environment(AppModel.self) private var model
    let insights: [LogInsight]
    let onShowSource: (String) -> Void
    @State private var expanded = true

    var body: some View {
        if !insights.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                DisclosureGroup(isExpanded: $expanded) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(insights) { insight in
                            row(insight)
                        }
                    }
                    .padding(.top, 6)
                } label: {
                    Label("What SMAPI is telling you (\(insights.count))", systemImage: "lightbulb")
                        .font(.headline)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.bar)
            Divider()
        }
    }

    @ViewBuilder
    private func row(_ insight: LogInsight) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: insight.level.symbol)
                .foregroundStyle(insight.level.color)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title(insight)).fontWeight(.semibold)
                Text(detail(insight)).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            actions(insight)
        }
    }

    private func title(_ insight: LogInsight) -> String {
        switch insight.kind {
        case .skippedMod(let name, _, let missing, let smapi):
            if !missing.isEmpty { return "\(name) didn't load: it needs mods you don't have" }
            if smapi != nil { return "\(name) didn't load: it needs a newer SMAPI" }
            return "\(name) didn't load"
        case .modErrors(let source, let count, _):
            return "\(source) had \(count) error\(count == 1 ? "" : "s") while you played"
        case .updatesAvailable(let list):
            return "\(list.count) mod update\(list.count == 1 ? "" : "s") available"
        case .smapiUpdate(let version, _):
            return "SMAPI \(version) is available"
        }
    }

    private func detail(_ insight: LogInsight) -> String {
        switch insight.kind {
        case .skippedMod(_, let reason, let missing, let smapi):
            if !missing.isEmpty {
                let names = missing.map { model.record(forDependency: $0)?.name ?? $0 }
                return "Missing: " + names.joined(separator: ", ")
            }
            if let smapi, !smapi.isEmpty { return "It needs SMAPI \(smapi) or later." }
            return "SMAPI says: \(reason)."
        case .modErrors(_, _, let events):
            let during = events.isEmpty ? "" : " (during \(events.joined(separator: ", ")))"
            return "It may be broken or outdated\(during). Updating it often helps; if not, report it to its author with your log."
        case .updatesAvailable(let list):
            return list.map { "\($0.name) \($0.version)" }.joined(separator: ", ")
        case .smapiUpdate:
            return "Newer SMAPI versions fix bugs and support newer mods."
        }
    }

    @ViewBuilder
    private func actions(_ insight: LogInsight) -> some View {
        switch insight.kind {
        case .skippedMod(let name, _, let missing, let smapi):
            if !missing.isEmpty {
                Button("Install Missing") { model.installMissing(uniqueIDs: missing, neededBy: name) }
                    .task { await model.resolve(uniqueIDs: missing) }
            } else if smapi != nil {
                Button("Get SMAPI…") { model.getSMAPI() }
            } else if let mod = model.installedMod(named: name), let nexusID = model.nexusID(for: mod) {
                Button("Check for Update…") { model.nexusSheet = NexusSheetRequest(modID: nexusID) }
            }
        case .modErrors(let source, _, _):
            HStack {
                Button("Show Messages") { onShowSource(source) }
                if let mod = model.installedMod(named: source), let update = model.update(for: mod), let nexusID = model.nexusID(for: mod) {
                    Button("Update to \(update.version)") {
                        model.queueNexusInstalls([NexusInstallRequest(modID: nexusID, title: mod.displayName, version: update.version)])
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        case .updatesAvailable:
            Button("Open Updates") { model.sidebarSelection = .updates }
        case .smapiUpdate:
            Button("Get SMAPI…") { model.getSMAPI() }
        }
    }
}
