// Mods that replace the same game files, from SMAPI's log: SMAPI then
// uses the original files, so neither mod's version shows in the game.

import ModManagerCore
import SwiftUI

struct LogConflict: Hashable {
    let mods: [String]
    let assets: [String]
}

extension AppModel {
    func loadLogConflicts() async {
        guard let log = try? await Task.detached(operation: { try SMAPILog.load(from: SMAPILog.latestLogURL) }).value else { return }
        setLogConflicts(from: log.insights)
    }

    func setLogConflicts(from insights: [LogInsight]) {
        logConflicts = insights.compactMap { insight in
            if case .assetConflict(let mods, let assets) = insight.kind { return LogConflict(mods: mods, assets: assets) }
            return nil
        }
    }

    /// Conflicts involving any of `targets` that still apply: every mod in
    /// them is installed and enabled (the log may predate a fix).
    func conflicts(for targets: [ModInfo]) -> [(others: [String], assets: [String])] {
        guard targets.contains(where: \.isEnabled) else { return [] }
        var names = Set(targets.map { $0.displayName.lowercased() })
        for target in targets {
            if let group = group(containing: target) { names.insert(group.name.lowercased()) }
        }
        return logConflicts.compactMap { conflict in
            guard conflict.mods.contains(where: { names.contains($0.lowercased()) }) else { return nil }
            let others = conflict.mods.filter { !names.contains($0.lowercased()) }
            guard !others.isEmpty, others.allSatisfy({ installedMod(named: $0)?.isEnabled == true }) else { return nil }
            return (others, conflict.assets)
        }
    }
}

/// "Conflicts with Town Remix": shown in a mod's details.
struct ConflictsSection: View {
    @AppModelEnvironment private var model
    let targets: [ModInfo]

    var body: some View {
        let conflicts = model.conflicts(for: targets)
        if !conflicts.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label("Conflicts", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                ForEach(conflicts, id: \.others) { conflict in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text("Replaces the same game files as")
                            ForEach(conflict.others, id: \.self) { name in
                                Button(name) {
                                    if let mod = model.installedMod(named: name) {
                                        model.reveal(rowID: model.group(containing: mod)?.id ?? mod.id)
                                    }
                                }
                                .buttonStyle(.link)
                            }
                        }
                        Text(Self.assetList(conflict.assets))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                Text("SMAPI can only use one, so it used the game's original files and neither change shows. Disable one of the mods to fix it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.callout)
            .padding(8)
            .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    /// "Maps/Town, Maps/Town_Fair and 3 more".
    static func assetList(_ assets: [String]) -> String {
        let shown = assets.prefix(3).joined(separator: ", ")
        return assets.count > 3 ? String(localized: "\(shown) and \(assets.count - 3) more") : shown
    }
}
