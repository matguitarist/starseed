// What went wrong during the last game session, from SMAPI's log: shown
// as a notification when the game closes.

import Foundation

public struct PlayReport: Sendable, Equatable {
    /// Mods SMAPI skipped at launch.
    public var notLoaded: [String] = []
    /// Mods that logged errors while the game ran, most errors first.
    public var withErrors: [String] = []
    /// Pairs of mods replacing the same game files.
    public var conflicts = 0
    /// SMAPI wrote a crash log for this session.
    public var crashed = false

    public var isEmpty: Bool { notLoaded.isEmpty && withErrors.isEmpty && conflicts == 0 && !crashed }

    public init(notLoaded: [String] = [], withErrors: [String] = [], conflicts: Int = 0, crashed: Bool = false) {
        self.notLoaded = notLoaded
        self.withErrors = withErrors
        self.conflicts = conflicts
        self.crashed = crashed
    }
}

extension SMAPILog {
    /// The problems worth telling the player about after a session. Update
    /// alerts are left out: the app already notifies about those.
    public func playReport(crashed: Bool) -> PlayReport {
        var report = PlayReport(crashed: crashed)
        for insight in insights {
            switch insight.kind {
            case .skippedMod(let name, _, _, _): report.notLoaded.append(name)
            case .modErrors(let source, _, _): report.withErrors.append(source)
            case .assetConflict: report.conflicts += 1
            case .updatesAvailable, .smapiUpdate: break
            }
        }
        return report
    }
}
