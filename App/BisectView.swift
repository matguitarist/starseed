// "Find a Broken Mod": a guided search that turns half of the suspect mods
// on per test (see Bisection in the core). The search is saved, so it
// survives quitting the app while the game runs; the mods enabled before
// it started are restored at the end.

import ModManagerCore
import SwiftUI

extension AppModel {
    private struct SavedBisection: Codable {
        var bisection: Bisection
        var originalEnabled: Set<String>
    }

    private static let bisectionKey = "bisection"

    /// Units to search: enabled mods, multi-part mods as one, each with the
    /// units it requires.
    func bisectionUnits() -> [Bisection.Unit] {
        let groups = allGroups.compactMap { group -> (ModGroup, [ModInfo])? in
            // SMAPI's own mods are never the cause: they stay on (see bundledKeys).
            let enabled = group.mods.filter { $0.isEnabled && !$0.isBundledWithSMAPI }
            return enabled.isEmpty ? nil : (group, enabled)
        }
        var unitByUniqueID: [String: String] = [:]
        for (group, mods) in groups {
            for mod in mods where !mod.uniqueID.isEmpty { unitByUniqueID[mod.uniqueID.lowercased()] = group.id }
        }
        return groups.map { group, mods in
            let needs = mods.flatMap { mod in
                mod.dependencies.filter(\.isRequired).map(\.uniqueID) + [mod.contentPackFor].compactMap { $0 }
            }
            let requires = Set(needs.compactMap { unitByUniqueID[$0.lowercased()] }).subtracting([group.id])
            return Bisection.Unit(id: group.id, name: group.name, modKeys: mods.map(Self.stableKey), requires: requires.sorted())
        }
    }

    func loadBisection() {
        guard let data = UserDefaults.standard.data(forKey: Self.bisectionKey),
              let saved = try? JSONDecoder().decode(SavedBisection.self, from: data)
        else { return }
        bisection = saved.bisection
        bisectionOriginal = saved.originalEnabled
    }

    private func saveBisection() {
        if let bisection, let bisectionOriginal,
           let data = try? JSONEncoder().encode(SavedBisection(bisection: bisection, originalEnabled: bisectionOriginal)) {
            UserDefaults.standard.set(data, forKey: Self.bisectionKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.bisectionKey)
        }
    }

    func startBisection() {
        let units = bisectionUnits()
        guard units.count >= 2 else { return }
        bisectionOriginal = enabledSnapshot
        bisection = Bisection(units: units)
        nextBisectionTest()
    }

    private func nextBisectionTest() {
        guard var current = bisection else { return }
        let ids = Set(current.startNextTest())
        bisection = current
        saveBisection()
        restoreEnabled(Set(current.units.filter { ids.contains($0.id) }.flatMap(\.modKeys)).union(bundledKeys))
    }

    /// SMAPI's own mods that were on when the search started: on in every test.
    private var bundledKeys: Set<String> {
        let original = bisectionOriginal ?? []
        return Set(mods.filter(\.isBundledWithSMAPI).map(Self.stableKey)).intersection(original)
    }

    func recordBisection(problemHappened: Bool) {
        guard var current = bisection else { return }
        guard !isGameRunning else {
            return show("Quit Stardew Valley First", "The next test changes which mods are on, and mods are only loaded when the game starts.")
        }
        current.record(problemHappened: problemHappened)
        bisection = current
        if current.isFinished {
            saveBisection()
        } else {
            nextBisectionTest()
        }
    }

    /// Ends the search and puts the mods back as they were, optionally
    /// leaving the culprit off.
    func endBisection(disablingCulprit: Bool) {
        guard var enabled = bisectionOriginal else { return }
        guard !isGameRunning else {
            return show("Quit Stardew Valley First", "Your mods can't be put back while the game is running.")
        }
        if disablingCulprit, let culprit = bisection?.culprit {
            enabled.subtract(culprit.modKeys)
        }
        bisection = nil
        bisectionOriginal = nil
        saveBisection()
        restoreEnabled(enabled)
    }

    /// The mods on for the current test, by name.
    var bisectionTestNames: [String] {
        guard let bisection, let testing = bisection.testing else { return [] }
        return testing.compactMap { bisection.unit($0)?.name }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}

struct BisectView: View {
    @AppModelEnvironment private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let bisection = model.bisection {
                if let culprit = bisection.culprit {
                    found(culprit)
                } else if bisection.isInconclusive {
                    inconclusive
                } else {
                    test(bisection)
                }
            } else {
                intro
            }
        }
        .padding(24)
        .frame(width: 520)
    }

    // MARK: Steps

    private var intro: some View {
        let count = model.bisectionUnits().count
        return VStack(alignment: .leading, spacing: 14) {
            Label("Find a Broken Mod", systemImage: "magnifyingglass")
                .font(.title2.bold())
            Text("When something goes wrong but the log doesn't say which mod is to blame, Starseed can find it by testing half of your mods at a time.")
            VStack(alignment: .leading, spacing: 6) {
                step(1, "Starseed turns some mods off.")
                step(2, "You play until you can tell whether the problem happens.")
                step(3, "You tell Starseed, and it picks the next half.")
            }
            Text("Your \(model.mods.filter(\.isEnabled).count) enabled mods make \(count) groups to test (parts of one mod, and mods with what they need, stay together): about \(Self.testCount(count)) tests. At the end, your mods are put back as they were.")
                .foregroundStyle(.secondary)
            Label("Don't go to bed in the game during tests: Stardew Valley saves overnight, and saving with mods off can lose their content. Quit to the title screen instead.", systemImage: "moon.zzz")
                .font(.callout)
                .padding(10)
                .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Start") { model.startBisection() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(count < 2)
            }
        }
    }

    private func test(_ bisection: Bisection) -> some View {
        let names = model.bisectionTestNames
        return VStack(alignment: .leading, spacing: 14) {
            Text("Test \(bisection.round) of about \(bisection.round + bisection.testsLeft - 1)")
                .font(.title2.bold())
            Text("\(names.count) of \(bisection.units.count) mods are on. Play, try what went wrong before, then come back here.")
            DisclosureGroup("Mods on for this test") {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(names, id: \.self) { Text($0).font(.callout) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 140)
            }
            Button {
                model.launchGame()
            } label: {
                Label("Play", systemImage: "play.fill")
            }
            Text("Did the problem happen?").font(.headline)
            HStack {
                Button("Yes, it happened") { model.recordBisection(problemHappened: true) }
                Button("No, everything was fine") { model.recordBisection(problemHappened: false) }
            }
            .controlSize(.large)
            Divider()
            HStack {
                Button("Stop and Restore My Mods") {
                    model.endBisection(disablingCulprit: false)
                    dismiss()
                }
                Spacer()
                Button("Continue Later") { dismiss() }
                    .help("Your progress is kept; the Installed list has a button to come back")
            }
        }
    }

    private func found(_ culprit: Bisection.Unit) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Found it: \(culprit.name)", systemImage: "checkmark.seal.fill")
                .font(.title2.bold())
                .foregroundStyle(.green)
            Text("The problem happened whenever \(culprit.name) was on, and not without it.")
            Text("Check for an update or a known issue on its page, or keep it off for now. It might also clash with another mod; the SMAPI log usually tells.")
                .foregroundStyle(.secondary)
            if let mod = model.mods.first(where: { culprit.modKeys.contains(AppModel.stableKey($0)) }),
               let nexusID = model.nexusID(for: mod) {
                Button("Open Its Nexus Page") { model.openInBrowser(NexusClient.modPageURL(nexusID)) }
                    .buttonStyle(.link)
            }
            HStack {
                Button("Restore Everything") {
                    model.endBisection(disablingCulprit: false)
                    dismiss()
                }
                Spacer()
                Button("Keep \(culprit.name) Off") {
                    model.endBisection(disablingCulprit: true)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var inconclusive: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("No single mod causes it", systemImage: "questionmark.circle")
                .font(.title2.bold())
            Text("The problem didn't happen with any half of your mods. It may need two mods together, come from the game itself, or not show up every time.")
            Text("The SMAPI log after the problem happens is the best clue; sharing it on smapi.io lets others help.")
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Restore My Mods") {
                    model.endBisection(disablingCulprit: false)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func step(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(verbatim: "\(number).").monospacedDigit().foregroundStyle(.secondary)
            Text(text)
        }
    }

    /// Tests to find one culprit among `count` units, plus a confirmation.
    static func testCount(_ count: Int) -> Int {
        count < 2 ? 0 : Int(log2(Double(count)).rounded(.up)) + 1
    }
}

/// Shown in Installed while a search is running.
struct BisectBanner: View {
    @AppModelEnvironment private var model

    var body: some View {
        if let bisection = model.bisection {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.tint)
                Text(bisection.isFinished ? String(localized: "The broken-mod search is done.")
                     : String(localized: "Finding a broken mod: test \(bisection.round). Some mods are off for now."))
                    .font(.callout)
                Spacer()
                Button(bisection.isFinished ? String(localized: "See Result") : String(localized: "Continue")) {
                    model.showBisect = true
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.tint.opacity(0.1))
            .overlay(alignment: .bottom) { Divider() }
        }
    }
}
