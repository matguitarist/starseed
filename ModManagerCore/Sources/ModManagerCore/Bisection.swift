// "Find the broken mod": tests half of the suspect mods at a time and keeps
// whichever half still shows the problem, until one is left (about log2(n)
// game launches). Multi-part mods move as one unit, and a unit is never
// tested without the units it requires.

import Foundation

public struct Bisection: Codable, Equatable, Sendable {
    public struct Unit: Codable, Hashable, Sendable, Identifiable {
        public let id: String
        public let name: String
        /// Stable keys of the unit's mods (paths without the "disabled" dot).
        public let modKeys: [String]
        /// IDs of the units it can't run without.
        public let requires: [String]

        public init(id: String, name: String, modKeys: [String], requires: [String]) {
            self.id = id
            self.name = name
            self.modKeys = modKeys
            self.requires = requires
        }
    }

    public let units: [Unit]
    /// Units that may still be the culprit, in test order (requirements first).
    public private(set) var suspects: [String]
    /// The units enabled for the current test (suspects being tested plus
    /// what they require), or nil before the first test.
    public private(set) var testing: [String]?
    public private(set) var round = 0
    /// Units that were on during a test where the problem happened. The
    /// last suspect only counts as the culprit if it's one of them; otherwise
    /// it gets a test of its own first.
    public private(set) var implicated: Set<String> = []

    public init(units: [Unit]) {
        self.units = units
        suspects = Self.ordered(units).map(\.id)
    }

    /// One culprit found (and seen causing the problem).
    public var culprit: Unit? {
        guard suspects.count == 1, implicated.contains(suspects[0]) else { return nil }
        return unit(suspects[0])
    }

    /// Every unit was cleared: the problem doesn't come from a single mod
    /// (two mods together, the game itself, or it didn't happen this time).
    public var isInconclusive: Bool { suspects.isEmpty }

    public var isFinished: Bool { culprit != nil || isInconclusive }

    /// Tests still needed, at most.
    public var testsLeft: Int {
        if isFinished { return 0 }
        if suspects.count == 1 { return 1 }  // confirming the last one
        return Int((Double(suspects.count)).log2.rounded(.up))
    }

    public func unit(_ id: String) -> Unit? {
        units.first { $0.id == id }
    }

    /// Starts the next test: the first half of the suspects (in requirement
    /// order, so their requirements are earlier suspects or already
    /// cleared units) plus everything they require. Returns the units to
    /// enable; everything else stays off.
    @discardableResult
    public mutating func startNextTest() -> [String] {
        guard !isFinished else { return [] }
        let half = Array(suspects.prefix((suspects.count + 1) / 2))
        let enabled = closure(of: half)
        testing = units.map(\.id).filter(enabled.contains)
        round += 1
        return testing ?? []
    }

    /// Records whether the problem happened with the current test's mods.
    public mutating func record(problemHappened: Bool) {
        guard let testing else { return }
        let tested = Set(testing)
        suspects = suspects.filter { tested.contains($0) == problemHappened }
        if problemHappened { implicated.formUnion(suspects) }
        self.testing = nil
    }

    /// `ids` and every unit they require, directly or not.
    func closure(of ids: [String]) -> Set<String> {
        var result = Set<String>()
        var pending = ids
        while let id = pending.popLast() {
            guard result.insert(id).inserted, let unit = unit(id) else { continue }
            pending += unit.requires
        }
        return result
    }

    /// Requirements before the units that need them (cycles keep name order).
    static func ordered(_ units: [Unit]) -> [Unit] {
        let byID = Dictionary(units.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var visited = Set<String>()
        var result: [Unit] = []
        func visit(_ unit: Unit, path: Set<String>) {
            guard !visited.contains(unit.id), !path.contains(unit.id) else { return }
            for id in unit.requires.sorted() {
                if let required = byID[id] { visit(required, path: path.union([unit.id])) }
            }
            if visited.insert(unit.id).inserted { result.append(unit) }
        }
        for unit in units.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) {
            visit(unit, path: [])
        }
        return result
    }
}

private extension Double {
    var log2: Double { Foundation.log2(self) }
}
